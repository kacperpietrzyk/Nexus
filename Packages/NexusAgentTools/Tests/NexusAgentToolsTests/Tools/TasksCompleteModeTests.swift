import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct TasksCompleteModeTests {
    @Test("strict mode throws when an open subtask exists")
    func strictBlocks() async throws {
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child")
        child.parentTaskID = parent.id
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])
        let args = JSONValue.object([
            "task_id": .string(parent.id.uuidString),
            "mode": .string("strict"),
        ])
        await #expect(throws: (any Error).self) {
            _ = try await TasksCompleteTool().call(args: args, context: fixture.context)
        }
        #expect(parent.lastCompletedAt == nil)
    }

    @Test("default mode completes the task")
    func defaultCompletes() async throws {
        let task = TaskItem(title: "Solo")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let args = JSONValue.object(["task_id": .string(task.id.uuidString)])
        _ = try await TasksCompleteTool().call(args: args, context: fixture.context)
        #expect(task.lastCompletedAt != nil)
    }

    @Test("cascade mode completes parent and child")
    func cascadeCompletes() async throws {
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child")
        child.parentTaskID = parent.id
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])
        let args = JSONValue.object([
            "task_id": .string(parent.id.uuidString),
            "mode": .string("cascade"),
        ])
        _ = try await TasksCompleteTool().call(args: args, context: fixture.context)
        #expect(parent.lastCompletedAt != nil)
        #expect(child.lastCompletedAt != nil)
    }
}
