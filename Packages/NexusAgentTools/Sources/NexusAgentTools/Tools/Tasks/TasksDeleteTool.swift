import Foundation
import NexusCore
import SwiftData

public struct TasksDeleteTool: AgentTool {
    public let name = "tasks.delete"
    public let description =
        "Soft-delete a task by UUID and remove it from the live search index immediately."
    public let inputSchema: JSONSchema = .object(
        properties: ["task_id": .string(description: "Task UUID to soft-delete.")],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.id == id
            }
        )
        guard let task = try context.modelContext.context.fetch(descriptor).first else {
            throw AgentError.notFound("Task not found: \(id.uuidString)")
        }

        if task.deletedAt == nil {
            try context.taskRepository.repository.softDelete(task)
        }
        await context.searchIndex.remove(kind: task.kind, id: task.id)

        return .object(["success": .bool(true)])
    }
}
