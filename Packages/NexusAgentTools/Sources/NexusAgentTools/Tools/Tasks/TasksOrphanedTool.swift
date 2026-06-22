import Foundation
import NexusCore

// MARK: - tasks.orphaned

/// Surfaces the "trust gap": live tasks whose project was soft-deleted (or was
/// never migrated in). Use the result to reassign tasks to a live project or
/// mark them complete/deleted so they stop silently polluting active counts.
///
/// Excludes soft-deleted tasks, templates, and tasks with no project assignment
/// (unassigned tasks are in the GTD inbox, not orphaned). See also
/// `projects.list(include_archived:true)` which surfaces archived project shells.
public struct TasksOrphanedTool: AgentTool {
    public let name = "tasks.orphaned"
    public let description = """
        Returns live tasks whose assigned project no longer exists (was deleted). \
        Useful after bulk migrations to find the trust gap — tasks that silently \
        vanish from project views because their project shell was removed. \
        Returns tasks sorted by title. Use tasks.update to reassign or tasks.delete \
        to clean up.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [:],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let orphans = try context.taskRepository.repository.orphanedTasks()
            .sorted { $0.title < $1.title }
        let dtos = try orphans.map { try TaskNotesContentStore.dto(for: $0, context: context) }
        return .object([
            "orphaned_tasks": try TasksToolJSON.encode(dtos),
            "count": .int(orphans.count),
        ])
    }
}
