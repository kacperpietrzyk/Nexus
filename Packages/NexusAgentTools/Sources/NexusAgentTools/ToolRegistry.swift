import Foundation

/// Holds an ordered list of `AgentTool`s. Lookup is O(n) but n=12 in 1h, acceptable.
/// Registry is built fresh per app launch in the composition root; not a singleton.
public struct ToolRegistry: Sendable {
    public let tools: [any AgentTool]

    public init(tools: [any AgentTool]) {
        self.tools = tools
    }

    public func tool(named: String) -> (any AgentTool)? {
        tools.last { $0.name == named }
    }

    public func manifest() -> ToolManifestDTO {
        let entries = tools.map { tool in
            ToolEntryDTO(
                name: tool.name,
                description: tool.description,
                inputSchema: tool.inputSchema
            )
        }
        return ToolManifestDTO(
            protocolVersion: AgentServiceConstants.protocolVersion,
            tools: entries
        )
    }
}
