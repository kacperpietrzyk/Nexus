import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

/// `tasks.update` duration-estimate plumbing (GAP #10). Split from
/// `TasksUpdateToolTests` to keep each suite under the type-body-length budget.
@Suite("TasksUpdateTool estimate")
struct TasksUpdateEstimateToolTests {
    @MainActor
    @Test("sets estimated_duration_minutes to seconds with explicit source")
    func setsEstimatedDuration() async throws {
        let task = TaskItem(title: "Refactor")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "estimated_duration_minutes": .int(45)
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.estimatedDurationSeconds == 2_700)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.estimatedDurationSeconds == 2_700)
        #expect(stored.durationSource == .explicit)
    }

    @MainActor
    @Test("clears estimate when estimated_duration_minutes is null")
    func clearsEstimate() async throws {
        let task = TaskItem(
            title: "Sized", estimatedDurationSeconds: 3_600, durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let dto = try await callUpdate(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "estimated_duration_minutes": .null
                ]),
            ]),
            context: fixture.context
        )

        #expect(dto.estimatedDurationSeconds == nil)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        #expect(stored.estimatedDurationSeconds == nil)
        #expect(stored.durationSource == nil)
    }

    @MainActor
    @Test("rejects non-positive estimated_duration_minutes on update")
    func rejectsNonPositiveEstimate() async throws {
        let task = TaskItem(title: "Task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["estimated_duration_minutes": .int(-5)]),
                ]),
                context: fixture.context
            )
        }
    }

    private func callUpdate(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksUpdateTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }
}
