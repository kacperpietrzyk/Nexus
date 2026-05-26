import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksSnoozeTool")
struct TasksSnoozeToolTests {
    @MainActor
    @Test("snoozes task to timestamp")
    func snoozeUntil() async throws {
        let task = TaskItem(title: "Snooze me")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callSnooze(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "until": .string("2026-12-31T17:00:00Z"),
            ]),
            context: fixture.context
        )

        #expect(dto.state == "open")
        #expect(dto.snoozeUntil == "2026-12-31T17:00:00.000Z")
    }

    @MainActor
    @Test("null until unsnoozes a future snooze")
    func nullUnsnoozesFutureSnooze() async throws {
        let task = TaskItem(title: "Wake me", status: .snoozed)
        task.snoozedUntil = Date(timeIntervalSince1970: 1_900_000_000)
        let fixture = try await InMemoryAgentContext.make(
            tasks: [task],
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let dto = try await callSnooze(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "until": .null,
            ]),
            context: fixture.context
        )

        #expect(dto.state == "open")
        #expect(dto.snoozeUntil == nil)
        #expect(task.snoozedUntil == nil)
    }

    @MainActor
    @Test("omitted until unsnoozes")
    func omittedUntilUnsnoozes() async throws {
        let task = TaskItem(title: "Wake me", status: .snoozed)
        task.snoozedUntil = Date(timeIntervalSince1970: 1_900_000_000)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callSnooze(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        #expect(dto.state == "open")
        #expect(dto.snoozeUntil == nil)
        #expect(task.snoozedUntil == nil)
    }

    @MainActor
    @Test("not found for soft-deleted task")
    func softDeletedNotFound() async throws {
        let task = TaskItem(title: "Deleted")
        task.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.notFound("Task not found: \(task.id.uuidString)")) {
            _ = try await TasksSnoozeTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "until": .string("2026-12-31T17:00:00Z"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects invalid until values")
    func invalidUntilValuesThrow() async throws {
        let task = TaskItem(title: "Task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.validation("until must be an ISO8601 string")) {
            _ = try await TasksSnoozeTool().call(
                args: .object(["task_id": .string(task.id.uuidString), "until": .int(1)]),
                context: fixture.context
            )
        }

        await #expect(throws: AgentError.validation("Invalid ISO8601 timestamp for field: until")) {
            _ = try await TasksSnoozeTool().call(
                args: .object(["task_id": .string(task.id.uuidString), "until": .string("tomorrow")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("snooze keeps task searchable")
    func snoozeKeepsSearchIndexFresh() async throws {
        let task = TaskItem(title: "Searchable snooze", body: "snooze-token")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await callSnooze(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "until": .string("2026-12-31T17:00:00Z"),
            ]),
            context: fixture.context
        )

        let result = try await TasksSearchTool().call(
            args: .object(["query": .string("snooze-token")]),
            context: fixture.context
        )
        let data = try JSONEncoder().encode(result)
        let response = try JSONDecoder().decode([TaskDTO].self, from: data)
        #expect(response.map(\.state) == ["open"])
        #expect(response.first?.snoozeUntil == "2026-12-31T17:00:00.000Z")
    }

    private func callSnooze(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksSnoozeTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }
}
