import NexusAgentTools

/// Extension target for tools that depend on TasksFeature.
public enum NexusAgentToolsExtras {
    public static let version = NexusAgentTools.version

    public static func tools() -> [any AgentTool] {
        [
            TasksCreateFromTextTool(),
            TasksDailySummaryTool(),
            BatchBeginTool(),
            BatchEndTool(),
        ]
    }
}
