import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository productivity")
struct TaskItemRepositoryProductivityTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("completedTasks counts only lastCompletedAt within the interval, skipping deleted/nil")
    func completedTasksInInterval() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })

        let startStamp: TimeInterval = 1_700_000_000
        let endStamp: TimeInterval = 1_700_086_400

        let inside = TaskItem(title: "inside")
        inside.lastCompletedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let before = TaskItem(title: "before")
        before.lastCompletedAt = Date(timeIntervalSince1970: 1_699_000_000)
        let never = TaskItem(title: "never")
        let deleted = TaskItem(title: "deleted")
        deleted.lastCompletedAt = Date(timeIntervalSince1970: 1_700_000_500)
        deleted.deletedAt = Date(timeIntervalSince1970: 1_700_000_600)
        // Defend the inclusive-end contract: a task completed exactly at the
        // interval start or end must count; one a second past the end must not.
        // Catches a regression from `<=` to `<` (or `>=` to `>` on the start side).
        let atStart = TaskItem(title: "atStart")
        atStart.lastCompletedAt = Date(timeIntervalSince1970: startStamp)
        let atEnd = TaskItem(title: "atEnd")
        atEnd.lastCompletedAt = Date(timeIntervalSince1970: endStamp)
        let afterEnd = TaskItem(title: "afterEnd")
        afterEnd.lastCompletedAt = Date(timeIntervalSince1970: endStamp + 1)
        for task in [inside, before, never, deleted, atStart, atEnd, afterEnd] {
            try repo.insert(task)
        }

        let interval = DateInterval(
            start: Date(timeIntervalSince1970: startStamp),
            end: Date(timeIntervalSince1970: endStamp)
        )
        let result = try repo.completedTasks(in: interval)
        #expect(Set(result.map(\.title)) == ["inside", "atStart", "atEnd"])
    }
}
