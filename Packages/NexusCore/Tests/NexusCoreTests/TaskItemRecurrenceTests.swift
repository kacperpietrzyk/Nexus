import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository.markDone")
struct TaskItemRecurrenceTests {
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
    @Test("non-recurring marks done without creating another task")
    func nonRecurring() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let task = TaskItem(title: "one-shot")
        try repo.insert(task)

        try repo.markDone(task)

        #expect(task.statusRaw == TaskStatus.done.rawValue)
        #expect(task.lastCompletedAt == now)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 1)
    }

    @MainActor
    @Test("daily recurrence creates next instance and preserves parent chain")
    func dailyRollsForward() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let original = TaskItem(title: "stretch", tags: ["health"], recurrenceRule: "FREQ=DAILY")
        try repo.insert(original)

        try repo.markDone(original)
        let second = try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id != original.id }!
        #expect(second.statusRaw == TaskStatus.open.rawValue)
        #expect(second.recurrenceParentId == original.id)
        #expect(second.tags == ["health"])

        try repo.markDone(second)
        let third = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != original.id && $0.id != second.id }!
        #expect(third.recurrenceParentId == original.id)
    }

    @MainActor
    @Test("dedup prevents duplicate next occurrence")
    func dedup() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let parent = TaskItem(title: "stretch", recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        let nextDate = RRuleScheduler(calendar: .gregorianUTC)
            .next(after: now, rule: try RRuleParser.parse("FREQ=DAILY"))!
        try repo.insert(
            TaskItem(
                title: "stretch",
                dueAt: nextDate,
                recurrenceRule: "FREQ=DAILY",
                recurrenceParentId: parent.id
            )
        )

        try repo.markDone(parent)

        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)
    }

    @MainActor
    @Test("reopen removes the spawned next-occurrence so cycling Done/Reopen does not duplicate rows")
    func reopenRemovesSpawn() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let original = TaskItem(title: "stretch", recurrenceRule: "FREQ=DAILY")
        try repo.insert(original)

        try repo.markDone(original)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)

        try repo.reopen(original)

        let remaining = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == original.id)
        #expect(remaining.first?.statusRaw == TaskStatus.open.rawValue)
        #expect(remaining.first?.lastCompletedAt == nil)
    }

    @MainActor
    @Test("reopen on non-recurring task only flips status without touching siblings")
    func reopenNonRecurringIsLocal() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let task = TaskItem(title: "one-shot")
        try repo.insert(task)
        try repo.markDone(task)

        try repo.reopen(task)

        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 1)
    }

    @MainActor
    @Test("COUNT and UNTIL can stop rolling")
    func stopConditions() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (context, repo) = try makeRepo(now: now)
        let limited = TaskItem(title: "limited", recurrenceRule: "FREQ=DAILY;COUNT=1")
        try repo.insert(limited)
        try repo.markDone(limited)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 1)

        let expired = TaskItem(title: "expired", recurrenceRule: "FREQ=DAILY;UNTIL=20260101T000000Z")
        try repo.insert(expired)
        try repo.markDone(expired)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)
    }
}
