import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksDeleteTool")
struct TasksDeleteToolTests {
    @MainActor
    @Test("soft-deletes task and returns success")
    func softDeleteReturnsSuccess() async throws {
        let task = TaskItem(title: "Delete me", body: "delete-token")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let result = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        #expect(result["success"] == .bool(true))
    }

    @MainActor
    @Test("sets deletedAt on the task")
    func setsDeletedAt() async throws {
        let task = TaskItem(title: "Delete me")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        let rows = try fixture.context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.first?.deletedAt != nil)
    }

    @MainActor
    @Test("tasks.get returns notFound after delete")
    func getNotFoundAfterDelete() async throws {
        let task = TaskItem(title: "Delete me")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        await #expect(throws: AgentError.notFound("Task not found: \(task.id.uuidString)")) {
            _ = try await TasksGetTool().call(
                args: .object(["task_id": .string(task.id.uuidString)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("tasks.search no longer returns deleted task")
    func searchOmitsDeletedTask() async throws {
        let task = TaskItem(title: "Delete workshop", body: "delete-token")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        let result = try await TasksSearchTool().call(
            args: .object(["query": .string("delete-token")]),
            context: fixture.context
        )
        let data = try JSONEncoder().encode(result)
        let response = try JSONDecoder().decode([TaskDTO].self, from: data)

        #expect(response.isEmpty)
    }

    @MainActor
    @Test("unknown task id throws notFound")
    func unknownIDThrowsNotFound() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let id = UUID()

        await #expect(throws: AgentError.notFound("Task not found: \(id.uuidString)")) {
            _ = try await TasksDeleteTool().call(
                args: .object(["task_id": .string(id.uuidString)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("malformed task id throws validation")
    func malformedIDThrowsValidation() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Invalid UUID for field: task_id")) {
            _ = try await TasksDeleteTool().call(
                args: .object(["task_id": .string("not-a-uuid")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("delete retry on already-soft-deleted task returns success")
    func alreadySoftDeletedRetryReturnsSuccess() async throws {
        let task = TaskItem(title: "Deleted", body: "deleted-token")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let result = try await TasksDeleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let searchResult = try await TasksSearchTool().call(
            args: .object(["query": .string("deleted-token")]),
            context: fixture.context
        )
        let data = try JSONEncoder().encode(searchResult)
        let response = try JSONDecoder().decode([TaskDTO].self, from: data)

        #expect(result["success"] == .bool(true))
        #expect(task.deletedAt != nil)
        #expect(response.isEmpty)
    }
}
