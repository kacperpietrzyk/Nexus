import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("LiquidProjectsModel")
struct LiquidProjectsModelTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Project.self, TaskItem.self, Section.self, Note.self, Comment.self, Link.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// The subtask count fetch is project-scoped IN-STORE via the `if let`
    /// optional-membership #Predicate (the `?? sentinel` coalescing form fails
    /// SQL generation at runtime) — this exercises the real SwiftData predicate
    /// translation (a runtime risk, not a compile-time one) and the grouping
    /// on top of it.
    @Test("Reload counts comments and subtasks per project task, scoped to the project")
    @MainActor
    func cardCountsAreProjectScoped() throws {
        let context = try makeContext()

        let project = Project(name: "P", status: .active)
        context.insert(project)

        let taskA = TaskItem(title: "A", projectID: project.id)
        let taskB = TaskItem(title: "B", projectID: project.id)
        let outsider = TaskItem(title: "outside")
        // Templates carry projectID verbatim but are inert (I-D1): never on the board.
        let template = TaskItem(title: "tpl", projectID: project.id, isTemplate: true)
        context.insert(taskA)
        context.insert(taskB)
        context.insert(outsider)
        context.insert(template)

        // Two live subtasks of A, one soft-deleted subtask of A (excluded),
        // one subtask of the non-project task (excluded), one parentless task.
        context.insert(TaskItem(title: "A.1", parentTaskID: taskA.id))
        context.insert(TaskItem(title: "A.2", parentTaskID: taskA.id))
        let deletedSub = TaskItem(title: "A.gone", parentTaskID: taskA.id)
        deletedSub.deletedAt = .now
        context.insert(deletedSub)
        context.insert(TaskItem(title: "out.1", parentTaskID: outsider.id))
        context.insert(TaskItem(title: "loner"))

        // One live comment on B, one deleted comment on B (excluded), one on
        // the outsider (excluded).
        context.insert(Comment(itemID: taskB.id, itemKind: .task, body: "hi"))
        let deletedComment = Comment(itemID: taskB.id, itemKind: .task, body: "gone")
        deletedComment.deletedAt = .now
        context.insert(deletedComment)
        context.insert(Comment(itemID: outsider.id, itemKind: .task, body: "elsewhere"))
        try context.save()

        let model = LiquidProjectsModel()
        model.selectedProjectID = project.id
        model.reload(modelContext: context)

        #expect(model.loadError == nil)
        #expect(model.selectedProject?.id == project.id)
        #expect(model.tasks.map(\.title).sorted() == ["A", "B"])
        #expect(model.subtaskCountsByTask == [taskA.id: 2])
        #expect(model.commentCountsByTask == [taskB.id: 1])
    }

    @Test("First line of the canonical note skips blank lines and trims")
    @MainActor
    func firstLineSkipsBlanks() {
        let note = Note(title: "t")
        note.plainText = "\n   \n  Build the next thing  \nsecond line"
        #expect(LiquidProjectsModel.firstLine(of: note) == "Build the next thing")
        #expect(LiquidProjectsModel.firstLine(of: nil) == nil)
    }
}
