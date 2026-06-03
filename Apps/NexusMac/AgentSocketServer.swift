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
        queue.async { [weak self] in self?.serve(client) }
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
        do { request = try JSONDecoder().decode(AgentSocketRequest.self, from: frame) }
        catch { return encode(AgentSocketResponse(error: .init(code: -32_700, message: "bad request frame"))) }

        switch request.op {
        case .ping:
            return encode(AgentSocketResponse(enabled: isEnabled(), version: appVersion))
        case .manifest, .dispatch:
            // Implemented in Task 4.
            return encode(AgentSocketResponse(error: .init(code: -32_601, message: "not implemented")))
        }
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
