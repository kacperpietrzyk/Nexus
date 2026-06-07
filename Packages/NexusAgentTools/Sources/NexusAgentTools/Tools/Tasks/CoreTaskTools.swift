import Foundation

/// Convenience builder for all core tools that do not depend on TasksFeature.
/// Includes `tasks.*`, `comments.*`, and `note.*` tools.
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
            NotesCreateTool(),
            NotesUpdateTool(),
            NotesGetTool(),
            NotesListTool(),
            NotesSearchTool(),
            NotesLinkTool(),
        ]
    }
}
