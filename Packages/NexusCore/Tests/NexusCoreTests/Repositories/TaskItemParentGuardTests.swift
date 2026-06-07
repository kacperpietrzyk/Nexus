import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository validateParentAssignment")
struct TaskItemParentGuardTests {
    @MainActor
    private func makeRepo() throws -> (repo: TaskItemRepository, context: ModelContext) {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        return (repo, context)
    }

    // (a) self-parent throws

    @MainActor
    @Test("self-parent throws parentIsSelf")
    func selfParentThrows() throws {
        let (repo, context) = try makeRepo()
        let task = TaskItem(title: "Solo")
        context.insert(task)
        try context.save()

        #expect(throws: TaskItemRepositoryError.parentIsSelf(taskID: task.id)) {
            try repo.validateParentAssignment(taskID: task.id, proposedParentID: task.id)
        }
    }

    // (b) nonexistent parent throws

    @MainActor
    @Test("nonexistent parent throws parentNotFound")
    func nonexistentParentThrows() throws {
        let (repo, context) = try makeRepo()
        let task = TaskItem(title: "Orphan")
        context.insert(task)
        try context.save()
        let phantom = UUID()

        #expect(throws: TaskItemRepositoryError.parentNotFound(parentID: phantom)) {
            try repo.validateParentAssignment(taskID: task.id, proposedParentID: phantom)
        }
    }

    // (c) cycle throws

    @MainActor
    @Test("cycle throws parentCycle")
    func cycleThrows() throws {
        let (repo, context) = try makeRepo()
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        context.insert(parent)
        context.insert(child)
        try context.save()

        // Assigning child as parent's parent would create: parent → child → parent.
        #expect(throws: TaskItemRepositoryError.parentCycle(taskID: parent.id, parentID: child.id)) {
            try repo.validateParentAssignment(taskID: parent.id, proposedParentID: child.id)
        }
    }

    // (d) valid parent passes (no throw)

    @MainActor
    @Test("valid parent passes without throwing")
    func validParentPasses() throws {
        let (repo, context) = try makeRepo()
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child")
        context.insert(parent)
        context.insert(child)
        try context.save()

        // Should not throw.
        try repo.validateParentAssignment(taskID: child.id, proposedParentID: parent.id)
    }

    // Bonus: soft-deleted proposed parent is treated as nonexistent

    @MainActor
    @Test("soft-deleted proposed parent throws parentNotFound")
    func softDeletedParentThrows() throws {
        let (repo, context) = try makeRepo()
        let task = TaskItem(title: "Task")
        let deletedParent = TaskItem(title: "Deleted Parent")
        deletedParent.deletedAt = Date()
        context.insert(task)
        context.insert(deletedParent)
        try context.save()

        #expect(throws: TaskItemRepositoryError.parentNotFound(parentID: deletedParent.id)) {
            try repo.validateParentAssignment(taskID: task.id, proposedParentID: deletedParent.id)
        }
    }

    // Bonus: pre-existing stored cycle (not involving taskID) doesn't hang or throw

    @MainActor
    @Test("pre-existing stored cycle not involving taskID terminates cleanly")
    func preExistingCycleTerminates() throws {
        let (repo, context) = try makeRepo()
        // A ↔ B form a pre-existing cycle in the stored data.
        let taskA = TaskItem(title: "A")
        let taskB = TaskItem(title: "B")
        taskA.parentTaskID = taskB.id
        taskB.parentTaskID = taskA.id
        let newTask = TaskItem(title: "New")
        context.insert(taskA)
        context.insert(taskB)
        context.insert(newTask)
        try context.save()

        // Assigning A as new task's parent — the chain from A walks A→B→A (cycle),
        // but never reaches newTask.id, so no cycle error, just clean termination.
        // A exists and is non-deleted, so this must pass.
        try repo.validateParentAssignment(taskID: newTask.id, proposedParentID: taskA.id)
    }
}
