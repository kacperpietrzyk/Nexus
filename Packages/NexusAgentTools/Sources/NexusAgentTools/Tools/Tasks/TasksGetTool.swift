import Foundation
import NexusCore
import SwiftData

public struct TasksGetTool: AgentTool {
    public let name = "tasks.get"
    public let description = "Fetches one non-deleted task by UUID."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "task_id": .string(description: "Task UUID to fetch.")
        ],
        required: ["task_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["task_id"], field: "task_id")
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.id == id
                    && task.deletedAt == nil
            }
        )

        guard let task = try context.modelContext.context.fetch(descriptor).first else {
            throw AgentError.notFound("Task not found: \(id.uuidString)")
        }

        return try TasksToolJSON.encode(TaskDTO(from: task))
    }
}

enum TasksToolJSON {
    static func encode(_ value: some Encodable) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

enum TasksToolArguments {
    static func requiredString(_ value: JSONValue?, field: String) throws -> String {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        return text
    }

    static func requiredUUID(_ value: JSONValue?, field: String) throws -> UUID {
        let text = try requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("Invalid UUID for field: \(field)")
        }
        return id
    }

    static func boundedInt(
        _ value: JSONValue?,
        field: String,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let intValue = value.intValue, range.contains(intValue) else {
            throw AgentError.validation("Invalid integer for field: \(field)")
        }
        return intValue
    }

    static func minimumInt(
        _ value: JSONValue?,
        field: String,
        default defaultValue: Int,
        minimum: Int
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let intValue = value.intValue, intValue >= minimum else {
            throw AgentError.validation("Invalid integer for field: \(field)")
        }
        return intValue
    }
}
