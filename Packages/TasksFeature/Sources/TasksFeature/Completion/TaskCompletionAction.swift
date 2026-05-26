import NexusCore

@MainActor
public enum TaskCompletionAction {
    /// Strict completion: throws `TaskItemRepositoryError.parentHasOpenSubtasks`
    /// when `task` has open direct children. Interactive surfaces should catch
    /// that error and present a confirmation dialog before calling
    /// `cascadeComplete(_:repository:)`.
    public static func complete(_ task: TaskItem, repository: TaskItemRepository) throws {
        try repository.markDoneStrict(task)
    }

    /// Cascade completion: closes the parent together with the entire open
    /// subtree. Use only after the user has confirmed, or for non-interactive
    /// callers (App Intents, Watch relay) where prompting is not possible.
    public static func cascadeComplete(_ task: TaskItem, repository: TaskItemRepository) throws {
        try repository.cascadeComplete(task)
    }

    /// Convenience that falls back to cascade when the parent has open
    /// subtasks. Kept for non-interactive surfaces (App Intents, Watch
    /// payload handler, command palette) that have no UI to confirm with.
    /// Interactive surfaces should call `complete(_:repository:)` and prompt
    /// the user before calling `cascadeComplete(_:repository:)`.
    public static func completeOrCascade(_ task: TaskItem, repository: TaskItemRepository) throws {
        do {
            try complete(task, repository: repository)
        } catch TaskItemRepositoryError.parentHasOpenSubtasks(let parentID, _) where parentID == task.id {
            try cascadeComplete(task, repository: repository)
        }
    }
}
