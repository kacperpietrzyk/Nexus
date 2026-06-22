import Foundation
import NexusAgentTools
import NexusCore
import os

/// Listens on a unix-domain socket in the App Group container and answers framed
/// agent requests from the nexus-mcp sidecar. Replaces the dead NSXPCListener path.
///
/// Only the running app can serve these requests (the tools need the live
/// `ToolRegistry` + `@MainActor` SwiftData context), so when the app is not
/// running the socket simply does not exist and the sidecar connect fails.
final class AgentSocketServer: @unchecked Sendable {
    private let registry: ToolRegistry
    private let context: AgentContext
    private let activityLog: AgentActivityLog
    private let appVersion: String
    private let isEnabled: @Sendable () -> Bool

    private let queue = DispatchQueue(label: "com.kacperpietrzyk.Nexus.agentSocket", qos: .utility)
    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus.Mac", category: "AgentSocketServer")

    init(
        registry: ToolRegistry,
        context: AgentContext,
        activityLog: AgentActivityLog,
        appVersion: String,
        isEnabled: @escaping @Sendable () -> Bool
    ) {
        self.registry = registry
        self.context = context
        self.activityLog = activityLog
        self.appVersion = appVersion
        self.isEnabled = isEnabled
    }

    func start() {
        queue.async { [weak self] in self?.bindAndListen() }
    }

    func stop() {
        queue.async { [weak self] in self?.teardown() }
    }

    private func bindAndListen() {
        guard listenerFD < 0 else { return }
        guard let url = AgentServiceConstants.socketURL() else {
            logger.error("No App Group container; cannot create agent socket")
            return
        }
        let path = url.path
        guard path.utf8.count < 104 else {
            logger.error("Agent socket path too long: \(path.utf8.count, privacy: .public) bytes")
            return
        }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { logger.error("socket() failed: \(errno)"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { cstr in
                strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cstr, 103)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bindRC == 0 else { logger.error("bind() failed: \(errno)"); close(fd); return }
        guard listen(fd, 4) == 0 else { logger.error("listen() failed: \(errno)"); close(fd); return }

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source
        logger.info("Agent socket listening at \(path, privacy: .public)")
    }

    private func acceptOne() {
        let client = accept(listenerFD, nil, nil)
        guard client >= 0 else { return }
        // Serve each client on its own serial queue so a connection parked in
        // `serve()`'s blocking `read()` loop cannot starve the accept source (which
        // stays on `queue`) or any other client. The queue is retained by this
        // async block and auto-released when `serve()` returns on EOF.
        let clientQueue = DispatchQueue(
            label: "com.kacperpietrzyk.Nexus.agentSocket.client", qos: .utility)
        clientQueue.async { [weak self] in self?.serve(client) }
    }

    /// Reads framed requests on `client` until EOF; answers each in order.
    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { return }
            buffer.append(contentsOf: chunk[0..<n])
            while let frame = try? AgentFrameCodec.takeFrame(from: &buffer) {
                let response = handle(frame)
                let out = AgentFrameCodec.frame(response)
                _ = out.withUnsafeBytes { raw in write(client, raw.baseAddress, raw.count) }
            }
        }
    }

    private func handle(_ frame: Data) -> Data {
        let request: AgentSocketRequest
        do {
            request = try JSONDecoder().decode(AgentSocketRequest.self, from: frame)
        } catch {
            return encode(AgentSocketResponse(error: .init(code: -32_700, message: "bad request frame")))
        }

        switch request.op {
        case .ping:
            return encode(AgentSocketResponse(enabled: isEnabled(), version: appVersion))
        case .manifest:
            guard isEnabled() else {
                return encode(AgentSocketResponse(error: .init(code: -32_001, message: "mcp disabled")))
            }
            do {
                let data = try JSONEncoder().encode(registry.manifest())
                return encode(AgentSocketResponse(payload: data))
            } catch {
                return encode(AgentSocketResponse(error: .init(code: -32_603, message: "manifest encode failed")))
            }
        case .dispatch:
            guard isEnabled() else {
                return encode(AgentSocketResponse(error: .init(code: -32_001, message: "mcp disabled")))
            }
            guard let name = request.name else {
                return encode(AgentSocketResponse(error: .init(code: -32_602, message: "missing tool name")))
            }
            return dispatchSync(name: name, argsJSON: request.argsJSON ?? Data("{}".utf8))
        }
    }

    /// Runs the tool on the main actor and blocks the socket worker thread until
    /// it completes. The sidecar issues one request at a time per connection.
    private func dispatchSync(name: String, argsJSON: Data) -> Data {
        let started = Date()
        let registry = self.registry
        let context = self.context
        let activityLog = self.activityLog
        let argsPreview = argsJSON.agentRedactedPreviewString()

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task { @MainActor in
            defer { semaphore.signal() }
            do {
                guard let tool = registry.tool(named: name) else {
                    throw AgentError.notFound("no tool named \(name)")
                }
                let args: JSONValue
                do {
                    args = try JSONDecoder().decode(JSONValue.self, from: argsJSON)
                } catch {
                    throw AgentError.validation("Invalid JSON arguments")
                }
                let result = try await tool.call(args: args, context: context)
                box.data = try JSONEncoder().encode(result)
                activityLog.record(
                    .success(
                        name: name, argsRedacted: argsPreview,
                        durationMs: Int(Date().timeIntervalSince(started) * 1_000)))
            } catch let agentError as AgentError {
                box.agentError = agentError
                activityLog.record(
                    .failure(
                        name: name, argsRedacted: argsPreview,
                        code: agentError.jsonRPCCode,
                        durationMs: Int(Date().timeIntervalSince(started) * 1_000)))
            } catch {
                let wrapped = AgentError.internalError("\(error)")
                box.agentError = wrapped
                activityLog.record(
                    .failure(
                        name: name, argsRedacted: argsPreview,
                        code: wrapped.jsonRPCCode,
                        durationMs: Int(Date().timeIntervalSince(started) * 1_000)))
            }
        }
        semaphore.wait()
        if let data = box.data { return encode(AgentSocketResponse(payload: data)) }
        let err = box.agentError ?? AgentError.internalError("no result")
        return encode(AgentSocketResponse(error: .init(code: err.jsonRPCCode, message: "\(err)")))
    }

    private func encode(_ response: AgentSocketResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data()
    }

    private func teardown() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenerFD >= 0 { close(listenerFD); listenerFD = -1 }
        if let url = AgentServiceConstants.socketURL() { unlink(url.path) }
    }
}

private final class ResultBox: @unchecked Sendable {
    var data: Data?
    var agentError: AgentError?
}

extension Data {
    /// First 512 characters of pretty-printed JSON shape for the activity log preview.
    fileprivate func agentRedactedPreviewString() -> String {
        guard let object = try? JSONSerialization.jsonObject(with: self) else {
            return "<invalid json: \(count) bytes>"
        }
        let redacted = Self.redactedJSONValue(object)
        guard JSONSerialization.isValidJSONObject(redacted),
            let pretty = try? JSONSerialization.data(
                withJSONObject: redacted,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return "<unprintable json: \(count) bytes>"
        }
        return String(string.prefix(512))
    }

    private static func redactedJSONValue(_ value: Any) -> Any {
        switch value {
        case let object as [String: Any]:
            return object.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = redactedJSONValue(entry.value)
            }
        case let array as [Any]:
            return array.map(redactedJSONValue)
        case is String:
            return "<redacted>"
        case is NSNull:
            return NSNull()
        case let number as NSNumber:
            return number
        default:
            return "<redacted>"
        }
    }
}
