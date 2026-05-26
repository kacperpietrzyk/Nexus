import Foundation
import NexusCore

public struct TasksCompleteTool: AgentTool {
    public let name = "tasks.complete"
    public let description =
        "Mark a task as done. Recurring tasks may create their next occurrence."
    public let inputSchema: JSONSchema = .object(
        properties: ["task_id": .string(description: "Task UUID to complete.")],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
        if task.status != .done {
            try completeOrCascade(task, repository: context.taskRepository.repository)
        }

        for row in try TasksMutationToolSupport.allTasks(in: context) where row.deletedAt == nil {
            await TasksToolSearchIndexing.reflect(row, in: context.searchIndex)
        }
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }

    @MainActor
    private func completeOrCascade(_ task: TaskItem, repository: TaskItemRepository) throws {
        do {
            try repository.markDoneStrict(task)
        } catch TaskItemRepositoryError.parentHasOpenSubtasks(let parentID, _) where parentID == task.id {
            try repository.cascadeComplete(task)
        }
    }
}
