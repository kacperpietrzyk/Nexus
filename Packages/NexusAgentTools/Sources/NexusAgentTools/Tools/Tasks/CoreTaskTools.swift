import Foundation

/// Convenience builder for all core tools that do not depend on TasksFeature.
/// Includes `tasks.*` and `comments.*` tools.
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
            CommentsListTool(),
            CommentsAddTool(),
            CommentsEditTool(),
            CommentsDeleteTool(),
        ]
    }
}
