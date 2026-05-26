import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("TaskCompletionAction strict path")
struct TaskCompletionActionTests {
    @Test("complete throws parentHasOpenSubtasks and does not mark parent done")
    @MainActor
    func completeRejectsParentWithOpenChildren() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 100)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        [parent, child].forEach(context.insert)
        try context.save()

        var thrown: Error?
        do {
            try TaskCompletionAction.complete(parent, repository: repository)
        } catch {
            thrown = error
        }

        let repoError = try #require(thrown as? TaskItemRepositoryError)
        guard case .parentHasOpenSubtasks(let parentID, let openCount) = repoError else {
            Issue.record("Expected parentHasOpenSubtasks, got \(repoError)")
            return
        }
        #expect(parentID == parent.id)
        #expect(openCount == 1)

        #expect(parent.status == .open)
        #expect(parent.lastCompletedAt == nil)
        #expect(child.status == .open)
    }

    @Test("cascadeComplete closes the parent together with its subtree")
    @MainActor
    func cascadeCompleteClosesEverything() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 200)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        [parent, child].forEach(context.insert)
        try context.save()

        try TaskCompletionAction.cascadeComplete(parent, repository: repository)

        #expect(parent.status == .done)
        #expect(child.status == .done)
        #expect(parent.lastCompletedAt == stamp)
        #expect(child.lastCompletedAt == stamp)
    }

    @Test("cascade confirmation prompt pluralizes its dialog title")
    func cascadePromptPluralization() {
        let single = CascadeCompletionPrompt(task: TaskItem(title: "Parent"), openCount: 1)
        #expect(single.dialogTitle.contains("1 subtask"))
        #expect(!single.dialogTitle.contains("subtasks"))

        let many = CascadeCompletionPrompt(task: TaskItem(title: "Parent"), openCount: 4)
        #expect(many.dialogTitle.contains("4 subtasks"))
    }
}
