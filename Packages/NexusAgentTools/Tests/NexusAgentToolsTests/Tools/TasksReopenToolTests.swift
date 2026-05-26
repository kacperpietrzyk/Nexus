import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksReopenTool")
struct TasksReopenToolTests {
    @MainActor
    @Test("reopens done task")
    func happyPath() async throws {
        let task = TaskItem(title: "Done task", status: .done)
        task.lastCompletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callReopen(taskID: task.id, context: fixture.context)

        #expect(dto.state == "open")
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
    }

    @MainActor
    @Test("reopen unsnoozes snoozed task")
    func reopenUnsnoozesSnoozedTask() async throws {
        let task = TaskItem(title: "Snoozed task", status: .snoozed)
        task.snoozedUntil = Date(timeIntervalSince1970: 1_900_000_000)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callReopen(taskID: task.id, context: fixture.context)

        #expect(dto.state == "open")
        #expect(dto.snoozeUntil == nil)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.snoozedUntil == nil)
    }

    @MainActor
    @Test("reopen open recurring task is no-op and preserves sibling")
    func reopenOpenRecurringTaskDoesNotRemoveSibling() async throws {
        let due = try #require(ISO8601DateFormatter().date(from: "2026-05-06T09:00:00Z"))
        let task = TaskItem(
            title: "Open recurring",
            body: "recurring-open-token",
            dueAt: due,
            recurrenceRule: "FREQ=DAILY"
        )
        let sibling = TaskItem(
            title: "Open recurring",
            body: "recurring-open-token",
            dueAt: due.addingTimeInterval(86_400),
            recurrenceRule: "FREQ=DAILY",
            recurrenceParentId: task.id
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task, sibling])

        let dto = try await callReopen(taskID: task.id, context: fixture.context)
        let rows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        let response = try await search("recurring-open-token", context: fixture.context)

        #expect(dto.state == "open")
        #expect(rows.count == 2)
        #expect(response.count == 2)
    }

    @MainActor
    @Test("not found for soft-deleted task")
    func softDeletedNotFound() async throws {
        let task = TaskItem(title: "Deleted", status: .done)
        task.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.notFound("Task not found: \(task.id.uuidString)")) {
            _ = try await TasksReopenTool().call(
                args: .object(["task_id": .string(task.id.uuidString)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects invalid task id type")
    func invalidTaskIDTypeThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Missing required string field: task_id")) {
            _ = try await TasksReopenTool().call(
                args: .object(["task_id": .int(1)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("reopen refreshes search index and removes recurring spawn")
    func reopenRefreshesSearchIndex() async throws {
        let due = try #require(ISO8601DateFormatter().date(from: "2026-05-06T09:00:00Z"))
        let task = TaskItem(
            title: "Daily review",
            body: "recurrence-token",
            dueAt: due,
            recurrenceRule: "FREQ=DAILY"
        )
        let fixture = try await InMemoryAgentContext.make(
            tasks: [task],
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        _ = try await TasksCompleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        #expect(try await search("recurrence-token", context: fixture.context).count == 2)

        _ = try await callReopen(taskID: task.id, context: fixture.context)

        let response = try await search("recurrence-token", context: fixture.context)
        #expect(response.count == 1)
        #expect(response.first?.id == task.id.uuidString)
        #expect(response.first?.state == "open")
    }

    private func callReopen(taskID: UUID, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksReopenTool().call(
            args: .object(["task_id": .string(taskID.uuidString)]),
            context: context
        )
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }

    private func search(_ query: String, context: AgentContext) async throws -> [TaskDTO] {
        let result = try await TasksSearchTool().call(
            args: .object(["query": .string(query), "limit": .int(10)]),
            context: context
        )
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode([TaskDTO].self, from: data)
    }
}
