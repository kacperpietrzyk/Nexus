import Foundation
import NexusCore

public struct TasksCompleteTool: AgentTool {
    public let name = "tasks.complete"
    public let description =
        "Mark a task as done. Recurring tasks may create their next occurrence."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID to complete."),
            "mode": .string(
                enumValues: ["default", "strict", "cascade"],
                description:
                    "default = complete; strict = error if open subtasks; cascade = complete subtree."
            ),
        ],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
        let mode = args["mode"]?.stringValue ?? "default"
        if task.status != .done {
            let repository = context.taskRepository.repository
            switch mode {
            case "default": try completeOrCascade(task, repository: repository)
            case "strict": try repository.markDoneStrict(task)
            case "cascade": try repository.cascadeComplete(task)
            default: throw AgentError.validation("Invalid mode: \(mode)")
            }
        }

        for row in try TasksMutationToolSupport.allTasks(in: context) where row.deletedAt == nil {
            await TasksToolSearchIndexing.reflect(row, in: context.searchIndex)
        }
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: task, context: context))
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
