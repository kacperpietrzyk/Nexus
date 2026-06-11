import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("ActivityTools")
struct ActivityToolsTests {

    @MainActor
    @Test("complete via tool then activity.get returns the completed event")
    func completeThenGet() async throws {
        let task = TaskItem(title: "audited")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksCompleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )

        let result = try await ActivityGetTool().call(
            args: .object(["item_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([ActivityEntryDTO].self, from: result)
        #expect(dtos.map(\.eventKind) == ["completed"])
        #expect(dtos.first?.itemKind == "task")
        #expect(dtos.first?.itemID == task.id.uuidString)
    }

    @MainActor
    @Test("activity.get still reads a soft-deleted task's history (deleted tasks keep their audit trail)")
    func deletedTaskHistoryReadable() async throws {
        let task = TaskItem(title: "gone but audited")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        try fixture.repo.softDelete(task, cascade: false)

        let result = try await ActivityGetTool().call(
            args: .object(["item_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([ActivityEntryDTO].self, from: result)
        #expect(dtos.map(\.eventKind) == ["deleted"])
    }

    @MainActor
    @Test("rejects a malformed item_id")
    func rejectsBadID() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.validation("item_id must be a valid UUID")) {
            _ = try await ActivityGetTool().call(
                args: .object(["item_id": .string("not-a-uuid")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("rejects non-task item_kind (only tasks are recorded v1)")
    func rejectsNonTaskKind() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.validation("item_kind must be 'task'")) {
            _ = try await ActivityGetTool().call(
                args: .object([
                    "item_id": .string(UUID().uuidString),
                    "item_kind": .string("project"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("unknown task returns an empty list (read-only — no existence gate, deleted ids stay queryable)")
    func unknownTaskIsEmpty() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let result = try await ActivityGetTool().call(
            args: .object(["item_id": .string(UUID().uuidString)]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([ActivityEntryDTO].self, from: result)
        #expect(dtos.isEmpty)
    }
}
