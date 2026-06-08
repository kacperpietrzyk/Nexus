import Foundation
import NexusCore

public struct TasksReopenTool: AgentTool {
    public let name = "tasks.reopen"
    public let description = "Reopen a previously completed or snoozed task."
    public let inputSchema: JSONSchema = .object(
        properties: ["task_id": .string(description: "Task UUID to reopen.")],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let beforeIDs = Set(try TasksMutationToolSupport.allTasks(in: context).map(\.id))
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)

        switch task.status {
        case .done:
            try context.taskRepository.repository.reopen(task)
        case .snoozed:
            try context.taskRepository.repository.update(task) { task in
                task.statusRaw = TaskStatus.open.rawValue
                task.snoozedUntil = nil
                task.lastCompletedAt = nil
            }
        case .open:
            break
        }

        let rows = try TasksMutationToolSupport.allTasks(in: context)
        let afterIDs = Set(rows.map(\.id))
        for removedID in beforeIDs.subtracting(afterIDs) {
            await context.searchIndex.remove(kind: .task, id: removedID)
        }
        for row in rows where row.deletedAt == nil {
            await TasksToolSearchIndexing.reflect(row, in: context.searchIndex)
        }
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: task, context: context))
    }
}
