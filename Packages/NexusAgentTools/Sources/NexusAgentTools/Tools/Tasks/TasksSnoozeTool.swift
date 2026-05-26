import Foundation
import NexusCore

public struct TasksSnoozeTool: AgentTool {
    public let name = "tasks.snooze"
    public let description = "Snooze a task until an ISO8601 timestamp, or pass until: null to unsnooze."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID to snooze."),
            "until": .anyValue(description: "ISO8601 timestamp, or null to unsnooze."),
        ],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let task = try TasksMutationToolSupport.liveTask(id: id, context: context)

        if args["until"] == nil || args["until"] == .null {
            try context.taskRepository.repository.update(task) { task in
                task.snoozedUntil = nil
                task.statusRaw = TaskStatus.open.rawValue
            }
        } else {
            let untilValue = args["until"]
            guard let until = try TasksMutationToolSupport.iso8601Date(untilValue, field: "until") else {
                throw AgentError.validation("Missing required field: until")
            }
            try context.taskRepository.repository.snooze(task, until: until)
        }

        await TasksToolSearchIndexing.reflect(task, in: context.searchIndex)
        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}
