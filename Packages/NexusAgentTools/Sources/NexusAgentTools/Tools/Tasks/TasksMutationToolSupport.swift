import Foundation
import NexusCore
import SwiftData

enum TasksMutationToolSupport {
    @MainActor
    static func liveTask(id: UUID, context: AgentContext) throws -> TaskItem {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.id == id
                    && task.deletedAt == nil
            }
        )
        guard let task = try context.modelContext.context.fetch(descriptor).first else {
            throw AgentError.notFound("Task not found: \(id.uuidString)")
        }
        return task
    }

    @MainActor
    static func allTasks(in context: AgentContext) throws -> [TaskItem] {
        try context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
    }

    static func iso8601Date(_ value: JSONValue?, field: String) throws -> Date? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be an ISO8601 string")
        }
        guard let date = parseISO8601(text) else {
            throw AgentError.validation("Invalid ISO8601 timestamp for field: \(field)")
        }
        return date
    }

    static func parseISO8601(_ text: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
