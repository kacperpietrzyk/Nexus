import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// T1 completion-based recurrence (`ANCHOR=COMPLETION`): the next occurrence is
/// computed from the completion date, preserving the original due time-of-day.
@Suite("TaskItemRepository completion-anchored recurrence")
struct TaskItemCompletionAnchorTests {
    private static let calendar = Calendar.gregorianUTC

    private static func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @MainActor
    private func makeRepo(now: Date) throws -> (ModelContext, TaskItemRepository) {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(calendar: .gregorianUTC),
            now: { now }
        )
        return (context, repo)
    }

    @MainActor
    private func spawn(of task: TaskItem, in context: ModelContext) throws -> TaskItem {
        try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id != task.id })
    }

    @MainActor
    @Test("daily ANCHOR=COMPLETION spawns from the completion date, keeping the due time-of-day")
    func completionAnchoredDaily() throws {
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(
            title: "water plants",
            dueAt: Self.date(2026, 1, 1, 9),
            recurrenceRule: "FREQ=DAILY;ANCHOR=COMPLETION"
        )
        try repo.insert(task)

        try repo.markDone(task)

        let next = try spawn(of: task, in: context)
        #expect(next.dueAt == Self.date(2026, 1, 11, 9))
    }

    @MainActor
    @Test("default (no ANCHOR) still spawns from the due date — regression lock")
    func dueDateAnchoredUnchanged() throws {
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(
            title: "water plants",
            dueAt: Self.date(2026, 1, 1, 9),
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(task)

        try repo.markDone(task)

        let next = try spawn(of: task, in: context)
        #expect(next.dueAt == Self.date(2026, 1, 2, 9))
    }

    @MainActor
    @Test("ANCHOR=COMPLETION with no due date spawns from the completion stamp verbatim")
    func completionAnchoredWithoutDue() throws {
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(title: "stretch", recurrenceRule: "FREQ=DAILY;ANCHOR=COMPLETION")
        try repo.insert(task)

        try repo.markDone(task)

        let next = try spawn(of: task, in: context)
        #expect(next.dueAt == Self.date(2026, 1, 11, 14, 30))
    }

    @MainActor
    @Test("weekly BYDAY ANCHOR=COMPLETION lands on the next matching weekday after completion")
    func completionAnchoredWeekly() throws {
        // 2026-01-10 is a Saturday; the Monday after it is 2026-01-12.
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(
            title: "report",
            dueAt: Self.date(2026, 1, 5, 9),  // a Monday
            recurrenceRule: "FREQ=WEEKLY;BYDAY=MO;ANCHOR=COMPLETION"
        )
        try repo.insert(task)

        try repo.markDone(task)

        let next = try spawn(of: task, in: context)
        #expect(next.dueAt == Self.date(2026, 1, 12, 9))
    }

    @MainActor
    @Test("startAt shifts with the new due date (relative offset preserved)")
    func completionAnchoredShiftsStartAt() throws {
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(
            title: "workout",
            dueAt: Self.date(2026, 1, 1, 9),
            startAt: Self.date(2026, 1, 1, 8),
            recurrenceRule: "FREQ=DAILY;ANCHOR=COMPLETION"
        )
        try repo.insert(task)

        try repo.markDone(task)

        let next = try spawn(of: task, in: context)
        #expect(next.dueAt == Self.date(2026, 1, 11, 9))
        #expect(next.startAt == Self.date(2026, 1, 11, 8))
    }

    @MainActor
    @Test("editing the rule on a done task regenerates the spawn from the completion date")
    func regenerateHonorsCompletionAnchor() throws {
        let completion = Self.date(2026, 1, 10, 14, 30)
        let (context, repo) = try makeRepo(now: completion)
        let task = TaskItem(
            title: "water plants",
            dueAt: Self.date(2026, 1, 1, 9),
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(task)
        try repo.markDone(task)
        let originalSpawn = try spawn(of: task, in: context)
        #expect(originalSpawn.dueAt == Self.date(2026, 1, 2, 9))
        let originalSpawnID = originalSpawn.id

        try repo.update(task) { $0.recurrenceRule = "FREQ=DAILY;ANCHOR=COMPLETION" }

        let regenerated = try spawn(of: task, in: context)
        #expect(regenerated.id != originalSpawnID)
        #expect(regenerated.dueAt == Self.date(2026, 1, 11, 9))
    }
}
