import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TasksGetTool")
struct TasksGetToolTests {
    @MainActor
    @Test("returns the requested task")
    func happyPath() async throws {
        let task = TaskItem(title: "Write review", status: .done)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let result = try await TasksGetTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let dto = try decode(TaskDTO.self, from: result)

        #expect(dto.title == "Write review")
        #expect(dto.state == "done")
    }

    @MainActor
    @Test("unknown task id throws notFound")
    func unknownIDThrows() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let id = UUID()

        await #expect(throws: AgentError.notFound("Task not found: \(id.uuidString)")) {
            _ = try await TasksGetTool().call(
                args: .object(["task_id": .string(id.uuidString)]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("missing task_id throws validation")
    func missingIDThrowsValidation() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Missing required string field: task_id")) {
            _ = try await TasksGetTool().call(args: .object([:]), context: fixture.context)
        }
    }

    @MainActor
    @Test("malformed task_id throws validation")
    func malformedIDThrowsValidation() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("Invalid UUID for field: task_id")) {
            _ = try await TasksGetTool().call(
                args: .object(["task_id": .string("not-a-uuid")]),
                context: fixture.context
            )
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }
}
