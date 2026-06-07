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
}
