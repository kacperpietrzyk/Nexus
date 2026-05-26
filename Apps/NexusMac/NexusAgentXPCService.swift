import Foundation
import NexusAgentTools
import NexusCore

/// XPC service hosted by NexusMac. It exposes the stable XPC interface and
/// dispatches calls into the shared agent tool registry on the main actor.
final class NexusAgentXPCService: NSObject, NSXPCListenerDelegate {
    fileprivate let registry: ToolRegistry
    fileprivate let context: AgentContext
    fileprivate let activityLog: AgentActivityLog
    fileprivate let appVersion: String
    fileprivate let isEnabled: @Sendable () -> Bool

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

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: NexusAgentXPCProtocol.self)
        newConnection.exportedObject = ExportedObject(service: self)
        newConnection.resume()
        return true
    }
}

/// XPC exports Objective-C objects, so this wrapper owns the `@objc` protocol
/// conformance and delegates actual work to `NexusAgentXPCService`.
@objc private final class ExportedObject: NSObject, NexusAgentXPCProtocol {
    private let service: NexusAgentXPCService

    init(service: NexusAgentXPCService) {
        self.service = service
    }

    func ping(reply: @escaping @Sendable (Bool, String) -> Void) {
        let enabled = service.isEnabled()
        let version = service.appVersion
        reply(enabled, version)
    }

    func getToolManifest(reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        guard service.isEnabled() else {
            reply(nil, AgentError.mcpDisabled.asNSError)
            return
        }

        do {
            let data = try JSONEncoder().encode(service.registry.manifest())
            reply(data, nil)
        } catch {
            reply(nil, AgentError.internalError("manifest encode failed: \(error)").asNSError)
        }
    }

    func dispatchTool(name: String, argsJSON: Data, reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        guard service.isEnabled() else {
            reply(nil, AgentError.mcpDisabled.asNSError)
            return
        }

        let started = Date()
        let registry = service.registry
        let context = service.context
        let activityLog = service.activityLog
        let argsPreview = argsJSON.redactedPreviewString()

        Task { @MainActor in
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
                let resultData = try JSONEncoder().encode(result)
                let durationMs = Int(Date().timeIntervalSince(started) * 1_000)
                activityLog.record(.success(name: name, argsRedacted: argsPreview, durationMs: durationMs))
                reply(resultData, nil)
            } catch let agentError as AgentError {
                let durationMs = Int(Date().timeIntervalSince(started) * 1_000)
                activityLog.record(
                    .failure(
                        name: name,
                        argsRedacted: argsPreview,
                        code: agentError.jsonRPCCode,
                        durationMs: durationMs
                    )
                )
                reply(nil, agentError.asNSError)
            } catch {
                let durationMs = Int(Date().timeIntervalSince(started) * 1_000)
                let wrapped = AgentError.internalError("\(error)")
                activityLog.record(
                    .failure(
                        name: name,
                        argsRedacted: argsPreview,
                        code: wrapped.jsonRPCCode,
                        durationMs: durationMs
                    )
                )
                reply(nil, wrapped.asNSError)
            }
        }
    }
}

extension Data {
    /// First 512 characters of pretty-printed JSON shape for the activity log preview.
    fileprivate func redactedPreviewString() -> String {
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
