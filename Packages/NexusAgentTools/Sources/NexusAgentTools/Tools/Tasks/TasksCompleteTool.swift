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
        let mode = try resolveMode(args["mode"])
        if task.status != .done {
            let repository = context.taskRepository.repository
            switch mode {
            case .default: try completeOrCascade(task, repository: repository)
            case .strict: try repository.markDoneStrict(task)
            case .cascade: try repository.cascadeComplete(task)
            }
        }

        for row in try TasksMutationToolSupport.allTasks(in: context) where row.deletedAt == nil {
            await TasksToolSearchIndexing.reflect(row, in: context.searchIndex)
        }
        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: task, context: context))
    }

    private enum CompletionMode: String {
        case `default`, strict, cascade
    }

    /// Resolves the optional `mode` argument. An absent value defaults to
    /// `.default` (preserving legacy callers); a present value that is not a
    /// recognized mode string — including a non-string JSON type — throws a
    /// validation error rather than silently falling back.
    private func resolveMode(_ raw: JSONValue?) throws -> CompletionMode {
        guard let raw, raw != .null else { return .default }
        guard let string = raw.stringValue, let mode = CompletionMode(rawValue: string) else {
            throw AgentError.validation("Invalid mode: \(raw)")
        }
        return mode
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
