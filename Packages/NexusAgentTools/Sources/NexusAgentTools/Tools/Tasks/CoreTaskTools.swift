import Foundation

/// Convenience builder for all core `tasks.*` tools that do not depend on TasksFeature.
public enum CoreTaskTools {
    public static func all() -> [any AgentTool] {
        [
            TasksGetTool(),
            TasksListTool(),
            TasksSearchTool(),
            TasksCreateTool(),
            TasksCreateIdempotentTool(),
            TasksUpdateTool(),
            TasksCompleteTool(),
            TasksReopenTool(),
            TasksSnoozeTool(),
            TasksDeleteTool(),
        ]
    }
}
