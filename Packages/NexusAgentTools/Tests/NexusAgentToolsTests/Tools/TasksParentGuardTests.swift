import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

/// Tests that tasks.create / tasks.create_idempotent / tasks.update validate the
/// parent_id field against self-reference, nonexistent parents, and cycles.
@Suite("Tasks parent-assignment guard")
struct TasksParentGuardTests {

    // MARK: - tasks.update: self-parent

    @MainActor
    @Test("tasks.update rejects self-parent via parent_id")
    func updateRejectsSelfParent() async throws {
        let task = TaskItem(title: "Solo")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["parent_id": .string(task.id.uuidString)]),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.update: nonexistent parent

    @MainActor
    @Test("tasks.update rejects nonexistent parent_id")
    func updateRejectsNonexistentParent() async throws {
        let task = TaskItem(title: "Orphan")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let phantom = UUID()

        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "patch": .object(["parent_id": .string(phantom.uuidString)]),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.update: cycle (TDD red test — must FAIL before guard is added)

    @MainActor
    @Test("tasks.update rejects parent_id that would create a cycle")
    func updateRejectsCycle() async throws {
        // Build: grandparent G → parent P → child C
        // Then try to reparent G under C → cycle G→P→C→G.
        let grandparent = TaskItem(title: "Grandparent")
        let parent = TaskItem(title: "Parent", parentTaskID: grandparent.id)
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        let fixture = try await InMemoryAgentContext.make(tasks: [grandparent, parent, child])

        // Try to set grandparent's parent to child — grandparent is an ancestor of child,
        // so assigning child as grandparent's parent creates a cycle.
        await #expect(throws: AgentError.self) {
            _ = try await TasksUpdateTool().call(
                args: .object([
                    "task_id": .string(grandparent.id.uuidString),
                    "patch": .object(["parent_id": .string(child.id.uuidString)]),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.update: valid parent succeeds (regression guard)

    @MainActor
    @Test("tasks.update accepts a valid parent_id (regression: must not over-reject)")
    func updateAcceptsValidParent() async throws {
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child")
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])

        let result = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(child.id.uuidString),
                "patch": .object(["parent_id": .string(parent.id.uuidString)]),
            ]),
            context: fixture.context
        )

        let data = try JSONEncoder().encode(result)
        let dto = try JSONDecoder().decode(TaskDTO.self, from: data)
        #expect(dto.parentID == parent.id.uuidString)
    }

    // MARK: - tasks.update: clearing parent (null) must succeed

    @MainActor
    @Test("tasks.update null parent_id clears parent without validation")
    func updateNullParentClears() async throws {
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])

        let result = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(child.id.uuidString),
                "patch": .object(["parent_id": .null]),
            ]),
            context: fixture.context
        )

        let data = try JSONEncoder().encode(result)
        let dto = try JSONDecoder().decode(TaskDTO.self, from: data)
        #expect(dto.parentID == nil)
    }

    // MARK: - tasks.create: nonexistent parent

    @MainActor
    @Test("tasks.create rejects nonexistent parent_id")
    func createRejectsNonexistentParent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let phantom = UUID()

        await #expect(throws: AgentError.self) {
            _ = try await TasksCreateTool().call(
                args: .object([
                    "title": .string("Orphan"),
                    "parent_id": .string(phantom.uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.create: valid parent succeeds

    @MainActor
    @Test("tasks.create accepts a valid parent_id")
    func createAcceptsValidParent() async throws {
        let parent = TaskItem(title: "Parent")
        let fixture = try await InMemoryAgentContext.make(tasks: [parent])

        let result = try await TasksCreateTool().call(
            args: .object([
                "title": .string("Child"),
                "parent_id": .string(parent.id.uuidString),
            ]),
            context: fixture.context
        )

        let data = try JSONEncoder().encode(result)
        let dto = try JSONDecoder().decode(TaskDTO.self, from: data)
        #expect(dto.parentID == parent.id.uuidString)
    }

    // MARK: - tasks.create_idempotent: nonexistent parent (create branch)

    @MainActor
    @Test("tasks.create_idempotent rejects nonexistent parent_id on create branch")
    func idempotentCreateRejectsNonexistentParent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let phantom = UUID()

        await #expect(throws: AgentError.self) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("src:1"),
                    "title": .string("Orphan"),
                    "parent_id": .string(phantom.uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.create_idempotent: cycle on update branch

    @MainActor
    @Test("tasks.create_idempotent rejects cycle on update branch")
    func idempotentUpdateRejectsCycle() async throws {
        // parent has externalSourceID "src:parent".
        // child is a subtask of parent.
        // Second call with externalSourceID "src:parent" hits the update branch,
        // and tries to set parent's parent_id to child — creating a cycle.
        let parent = TaskItem(title: "Parent")
        parent.externalSourceID = "src:parent"
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        let fixture = try await InMemoryAgentContext.make(tasks: [parent, child])

        await #expect(throws: AgentError.self) {
            _ = try await TasksCreateIdempotentTool().call(
                args: .object([
                    "external_source_id": .string("src:parent"),
                    "title": .string("Parent"),
                    "parent_id": .string(child.id.uuidString),
                ]),
                context: fixture.context
            )
        }
    }
}
