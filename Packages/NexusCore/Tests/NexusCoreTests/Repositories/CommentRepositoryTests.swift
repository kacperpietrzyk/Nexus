import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("CommentRepository")
struct CommentRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Comment.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("add and list in chronological order")
    func addAndListChronological() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let taskID = UUID()
        let first = try repo.add(body: "one", to: taskID, kind: .task)
        let second = try repo.add(body: "two", to: taskID, kind: .task)

        let listed = try repo.comments(for: taskID, kind: .task)
        #expect(listed.map(\.id) == [first.id, second.id])
    }

    @MainActor
    @Test("edit updates body and timestamp")
    func editUpdatesBodyAndTimestamp() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let comment = try repo.add(body: "before", to: UUID(), kind: .task)
        try repo.edit(comment, body: "after")
        #expect(comment.body == "after")
        #expect(comment.updatedAt >= comment.createdAt)
    }

    @MainActor
    @Test("soft delete hides comment from list")
    func softDeleteHidesFromList() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let taskID = UUID()
        let comment = try repo.add(body: "gone", to: taskID, kind: .task)
        try repo.softDelete(comment)
        #expect(try repo.comments(for: taskID, kind: .task).isEmpty)
    }

    @MainActor
    @Test("list is scoped by item and kind")
    func listIsScopedByItemAndKind() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let shared = UUID()
        _ = try repo.add(body: "task one", to: shared, kind: .task)
        _ = try repo.add(body: "project one", to: shared, kind: .project)
        #expect(try repo.comments(for: shared, kind: .task).count == 1)
        #expect(try repo.comments(for: shared, kind: .project).count == 1)
    }

    @MainActor
    @Test("task soft delete cascades comments")
    func taskSoftDeleteCascadesComments() throws {
        let context = try makeContext()
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let commentRepo = CommentRepository(context: context)
        let task = TaskItem(title: "parent")
        try taskRepo.insert(task)
        _ = try commentRepo.add(body: "child note", to: task.id, kind: .task)

        try taskRepo.softDelete(task)
        #expect(try commentRepo.comments(for: task.id, kind: .task).isEmpty)
    }

    @MainActor
    @Test("task soft delete cascades comments across full subtask subtree")
    func taskSoftDeleteCascadesSubtaskComments() throws {
        let context = try makeContext()
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let commentRepo = CommentRepository(context: context)
        let parent = TaskItem(title: "parent")
        let subtask = TaskItem(title: "subtask", parentTaskID: parent.id)
        try taskRepo.insert(parent)
        try taskRepo.insert(subtask)
        _ = try commentRepo.add(body: "parent note", to: parent.id, kind: .task)
        _ = try commentRepo.add(body: "subtask note", to: subtask.id, kind: .task)

        try taskRepo.softDelete(parent)

        #expect(try commentRepo.comments(for: parent.id, kind: .task).isEmpty)
        #expect(try commentRepo.comments(for: subtask.id, kind: .task).isEmpty)
    }

    @MainActor
    @Test("project soft delete cascades comments")
    func projectSoftDeleteCascadesComments() throws {
        let context = try makeContext()
        let projectRepo = ProjectRepository(context: context)
        let commentRepo = CommentRepository(context: context)
        let project = try projectRepo.create(name: "commented project")
        _ = try commentRepo.add(body: "project note", to: project.id, kind: .project)

        try projectRepo.softDelete(project)

        #expect(project.deletedAt != nil)
        #expect(try commentRepo.comments(for: project.id, kind: .project).isEmpty)
    }

    @MainActor
    @Test("add with same external source id updates in place (no duplicate)")
    func addWithSameExternalSourceIDUpdatesInPlace() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let taskID = UUID()
        let first = try repo.add(body: "a", to: taskID, kind: .task, externalSourceID: "x")
        let second = try repo.add(body: "b", to: taskID, kind: .task, externalSourceID: "x")

        let listed = try repo.comments(for: taskID, kind: .task)
        #expect(listed.count == 1)
        #expect(listed.first?.body == "b")
        #expect(first.id == second.id)
    }

    @MainActor
    @Test("add with same external source id updates target anchor")
    func addWithSameExternalSourceIDUpdatesTargetAnchor() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let oldTaskID = UUID()
        let newTaskID = UUID()
        let first = try repo.add(body: "old", to: oldTaskID, kind: .task, externalSourceID: "x")
        let second = try repo.add(body: "new", to: newTaskID, kind: .task, externalSourceID: "x")

        #expect(first.id == second.id)
        #expect(try repo.comments(for: oldTaskID, kind: .task).isEmpty)
        let listed = try repo.comments(for: newTaskID, kind: .task)
        #expect(listed.map(\.id) == [first.id])
        #expect(listed.map(\.body) == ["new"])
    }

    @MainActor
    @Test("add with nil external source id always inserts")
    func addWithNilExternalSourceIDAlwaysInserts() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let taskID = UUID()
        _ = try repo.add(body: "same", to: taskID, kind: .task)
        _ = try repo.add(body: "same", to: taskID, kind: .task)

        #expect(try repo.comments(for: taskID, kind: .task).count == 2)
    }

    @MainActor
    @Test("re-import of a soft-deleted external id creates a fresh live row")
    func addAfterSoftDeleteCreatesFreshRow() throws {
        let context = try makeContext()
        let repo = CommentRepository(context: context)
        let taskID = UUID()
        let original = try repo.add(body: "a", to: taskID, kind: .task, externalSourceID: "x")
        try repo.softDelete(original)

        let reimported = try repo.add(body: "b", to: taskID, kind: .task, externalSourceID: "x")

        #expect(reimported.id != original.id)
        let listed = try repo.comments(for: taskID, kind: .task)
        #expect(listed.count == 1)
        #expect(listed.first?.id == reimported.id)
    }
}
