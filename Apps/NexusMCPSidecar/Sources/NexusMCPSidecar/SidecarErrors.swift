import Foundation

/// Mirror of NexusAgentTools.AgentError. The sidecar cannot import the shared
/// package because schemas and errors flow over XPC.
struct MCPError: Error, Sendable {
    let code: Int
    let message: String
}

enum SidecarErrors {
    static let appNotRunning = MCPError(
        code: -32_001,
        message: "Nexus.app is not running. Open it to enable MCP access."
    )

    static let mcpDisabled = MCPError(
        code: -32_002,
        message: "MCP server is disabled in Nexus Settings."
    )

    static func from(nsError: NSError) -> MCPError {
        let message = (nsError.userInfo[NSLocalizedDescriptionKey] as? String) ?? nsError.localizedDescription
        return MCPError(code: nsError.code, message: message)
    }
}
