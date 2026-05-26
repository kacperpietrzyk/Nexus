import Foundation
import NexusCore
import SwiftData

public struct TasksSearchTool: AgentTool {
    public let name = "tasks.search"
    public let description = "Searches live tasks by title, notes, and tags."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Search query."),
            "limit": .integer(minimum: 1, maximum: 200, description: "Maximum tasks to return."),
        ],
        required: ["query"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let query = try TasksToolArguments.requiredString(args["query"], field: "query")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AgentError.validation("Search query cannot be empty")
        }

        let limit = try TasksToolArguments.boundedInt(
            args["limit"],
            field: "limit",
            default: 50,
            range: 1...200
        )
        let indexedCount = await context.searchIndex.documentCount
        let hits = await context.searchIndex.search(query, kinds: [.task], limit: max(limit, indexedCount))
        guard !hits.isEmpty else {
            return .array([])
        }

        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = try context.modelContext.context.fetch(descriptor)
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let result = hits.compactMap { hit -> TaskDTO? in
            guard let task = tasksByID[hit.itemID], task.deletedAt == nil else { return nil }
            return TaskDTO(from: task)
        }
        return try TasksToolJSON.encode(Array(result.prefix(limit)))
    }
}
