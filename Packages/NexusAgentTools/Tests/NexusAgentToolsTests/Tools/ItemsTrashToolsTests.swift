import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct ItemsTrashToolsTests {
    @Test("list_deleted returns soft-deleted tasks only")
    func listsDeletedTasks() async throws {
        let live = TaskItem(title: "Live")
        let gone = TaskItem(title: "Gone")
        let fixture = try await InMemoryAgentContext.make(tasks: [live, gone])
        try fixture.context.taskRepository.repository.softDelete(gone)
        let args = JSONValue.object(["kind": .string("task")])
        let result = try await ItemsListDeletedTool().call(args: args, context: fixture.context)
        let items = result["items"]?.arrayValue ?? []
        #expect(items.count == 1)
        #expect(items.first?["title"]?.stringValue == "Gone")
        #expect(items.first?["kind"]?.stringValue == "task")
    }

    @Test("restore brings a soft-deleted task back to live")
    func restoresTask() async throws {
        let gone = TaskItem(title: "Gone")
        let fixture = try await InMemoryAgentContext.make(tasks: [gone])
        try fixture.context.taskRepository.repository.softDelete(gone)
        let args = JSONValue.object(["id": .string(gone.id.uuidString), "kind": .string("task")])
        _ = try await ItemsRestoreTool().call(args: args, context: fixture.context)
        #expect(gone.deletedAt == nil)
    }

    @Test("restore on a live (never-deleted) item is rejected and does not mutate it")
    func restoreLiveItemRejected() async throws {
        let live = TaskItem(title: "Live")
        let fixture = try await InMemoryAgentContext.make(tasks: [live])
        let before = live.updatedAt
        let args = JSONValue.object(["id": .string(live.id.uuidString), "kind": .string("task")])
        await #expect(throws: AgentError.self) {
            _ = try await ItemsRestoreTool().call(args: args, context: fixture.context)
        }
        // Not soft-deleted before, still not after; and the buggy path's `updatedAt` bump
        // must not have happened.
        #expect(live.deletedAt == nil)
        #expect(live.updatedAt == before)
    }

    @Test("restore on an unsupported kind is a validation error")
    func unsupportedKind() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object(["id": .string(UUID().uuidString), "kind": .string("scheduledBlock")])
        await #expect(throws: AgentError.self) {
            _ = try await ItemsRestoreTool().call(args: args, context: fixture.context)
        }
    }
}
