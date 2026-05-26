import Foundation

/// XPC interface between the running NexusMac process and the nexus-mcp sidecar.
///
/// JSON `Data` keeps the transport stable as tools are added: the XPC surface
/// stays at ping, manifest, and dispatch while tool schemas evolve in
/// NexusAgentTools.
@objc public protocol NexusAgentXPCProtocol {
    /// Sidecar handshake. `ok == false` means the MCP toggle is currently off.
    func ping(reply: @escaping @Sendable (_ ok: Bool, _ appVersion: String) -> Void)

    /// Returns JSON-encoded `ToolManifestDTO`.
    func getToolManifest(reply: @escaping @Sendable (_ manifestJSON: Data?, _ error: NSError?) -> Void)

    /// Dispatches a tool call. `argsJSON` is the full JSON object for the tool args.
    func dispatchTool(
        name: String,
        argsJSON: Data,
        reply: @escaping @Sendable (_ resultJSON: Data?, _ error: NSError?) -> Void
    )
}
