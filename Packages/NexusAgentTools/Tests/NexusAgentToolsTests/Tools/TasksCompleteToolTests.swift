import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksCompleteTool")
struct TasksCompleteToolTests {
    @MainActor
    @Test("marks open task as done")
    func happyPath() async throws {
        let task = TaskItem(title: "Finish report")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callComplete(taskID: task.id, context: fixture.context)

        #expect(dto.state == "done")
        #expect(task.statusRaw == TaskStatus.done.rawValue)
    }

    @MainActor
    @Test("complete cascades open subtasks")
    func completeCascadesOpenSubtasks() async throws {
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])

        let dto = try await callComplete(taskID: parent.id, context: fixture.context)

        #expect(dto.state == "done")
        #expect(parent.status == .done)
        #expect(child.status == .done)
    }

    @MainActor
    @Test("complete is idempotent for already done recurring task")
    func completeDoneRecurringTaskDoesNotDuplicateSpawn() async throws {
        let task = TaskItem(
            title: "Daily recurring",
            body: "done-idempotent-token",
            recurrenceRule: "FREQ=DAILY"
        )
        let fixture = try await InMemoryAgentContext.make(
            tasks: [task],
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        _ = try await callComplete(taskID: task.id, context: fixture.context)
        let firstRows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        _ = try await callComplete(taskID: task.id, context: fixture.context)
        let secondRows = try fixture.repo.context.fetch(FetchDescriptor<TaskItem>())
        // Task content (body) is no longer indexed — it lives in a `Note`
        // (spec §4.2/§13). Search the shared TITLE token; the parent + its recurring
        // spawn both carry it, so the idempotent re-complete still yields 2 rows.
        let response = try await search("recurring", context: fixture.context)

        #expect(firstRows.count == 2)
        #expect(secondRows.count == 2)
        #expect(response.count == 2)
    }

    @MainActor
    @Test("not found for soft-deleted task")
    func softDeletedNotFound() async throws {
        let task = TaskItem(title: "Deleted")
        task.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.notFound("Task not found: \(task.id.uuidString)")) {
            _ = try await TasksCompleteTool().call(
                args: .object(["task_id": .string(task.id.uuidString)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects invalid task id")
    func invalidTaskIDThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Invalid UUID for field: task_id")) {
            _ = try await TasksCompleteTool().call(
                args: .object(["task_id": .string("not-a-uuid")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("completion keeps mutated and spawned tasks searchable")
    func completionKeepsSearchIndexFresh() async throws {
        let due = try #require(ISO8601DateFormatter().date(from: "2026-05-06T09:00:00Z"))
        let task = TaskItem(
            title: "Daily stretch",
            body: "mobility",
            dueAt: due,
            recurrenceRule: "FREQ=DAILY"
        )
        let fixture = try await InMemoryAgentContext.make(
            tasks: [task],
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        _ = try await callComplete(taskID: task.id, context: fixture.context)

        // Task content (body) is no longer indexed — it lives in a `Note`
        // (spec §4.2/§13). Search the shared TITLE token; both the completed parent
        // and its freshly spawned open instance carry it.
        let response = try await search("stretch", context: fixture.context)
        #expect(response.count == 2)
        #expect(response.contains { $0.id == task.id.uuidString && $0.state == "done" })
        #expect(response.contains { $0.id != task.id.uuidString && $0.state == "open" })
    }

    private func callComplete(taskID: UUID, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksCompleteTool().call(
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
