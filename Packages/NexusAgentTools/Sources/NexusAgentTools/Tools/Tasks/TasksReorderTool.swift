import Foundation
import NexusCore

public struct TasksReorderTool: AgentTool {
    public let name = "tasks.reorder"
    public let description = """
        Persist a manual task order. Assigns sequential order following ordered_ids exactly. \
        Does not bump updatedAt, touch recurrence, or reschedule notifications.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "ordered_ids": .array(
                items: .string(description: "Task UUID"),
                description: "Task UUIDs in the desired display order."
            )
        ],
        required: ["ordered_ids"]
    )
    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        guard let raw = args["ordered_ids"]?.arrayValue, !raw.isEmpty else {
            throw AgentError.validation("ordered_ids must be a non-empty array")
        }
        var ids: [UUID] = []
        for value in raw {
            guard let text = value.stringValue, let id = UUID(uuidString: text) else {
                throw AgentError.validation("ordered_ids must contain task UUID strings")
            }
            ids.append(id)
        }
        var ordered: [TaskItem] = []
        for id in ids {
            let task = try TasksMutationToolSupport.liveTask(id: id, context: context)
            ordered.append(task)
        }
        try context.taskRepository.repository.reorder(ordered)
        return .object(["success": .bool(true), "count": .int(ordered.count)])
    }
}
