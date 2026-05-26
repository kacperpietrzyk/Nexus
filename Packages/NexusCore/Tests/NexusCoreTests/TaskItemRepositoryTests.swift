import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository")
struct TaskItemRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("insert persists the task")
    func insert() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        try repo.insert(TaskItem(title: "buy milk"))
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.count == 1)
    }

    @MainActor
    @Test("update mutates, normalizes tags, and bumps updatedAt")
    func update() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)
        try repo.update(task) {
            $0.title = "y"
            $0.tags = [" Email ", "email", "WORK", "", "work/projectA"]
        }
        #expect(task.title == "y")
        #expect(task.tags == ["email", "work", "work/projecta"])
        #expect(task.updatedAt == now)
    }

    @MainActor
    @Test("softDelete and snooze lifecycle")
    func lifecycle() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)

        let until = now.addingTimeInterval(3600)
        try repo.snooze(task, until: until)
        #expect(task.statusRaw == TaskStatus.snoozed.rawValue)
        #expect(task.snoozedUntil == until)

        try repo.softDelete(task)
        #expect(task.deletedAt == now)
    }

    @MainActor
    @Test("unsnooze clears only elapsed snoozes")
    func unsnooze() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)
        try repo.snooze(task, until: now.addingTimeInterval(3600))
        try repo.unsnooze(task)
        #expect(task.statusRaw == TaskStatus.snoozed.rawValue)

        try repo.snooze(task, until: now.addingTimeInterval(-3600))
        try repo.unsnooze(task)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.snoozedUntil == nil)
    }

    @MainActor
    @Test("markDone on already-done non-recurring task is no-op")
    func markDoneIdempotentNonRecurring() throws {
        let context = try makeContext()
        let firstStamp = Date(timeIntervalSince1970: 1_800_000_000)
        var current = firstStamp
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { current })
        let task = TaskItem(title: "x", dueAt: firstStamp)
        try repo.insert(task)

        try repo.markDone(task)
        let firstCompleted = task.lastCompletedAt
        #expect(firstCompleted == firstStamp)

        current = firstStamp.addingTimeInterval(60)
        try repo.markDone(task)
        #expect(task.lastCompletedAt == firstCompleted)
        #expect(task.statusRaw == TaskStatus.done.rawValue)
    }

    @MainActor
    @Test("markDone on already-done recurring task does not duplicate spawn")
    func markDoneIdempotentRecurring() throws {
        let context = try makeContext()
        let firstStamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { firstStamp })
        let parent = TaskItem(
            title: "weekly",
            dueAt: firstStamp,
            recurrenceRule: "FREQ=WEEKLY"
        )
        try repo.insert(parent)

        try repo.markDone(parent)
        let afterFirst = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(afterFirst.count == 2)

        try repo.markDone(parent)
        let afterSecond = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(afterSecond.count == 2)
    }

    @MainActor
    @Test("markDone on recurring task with startAt/endAt duration spawns child preserving duration")
    func markDoneRecurringPreservesStartEndDuration() throws {
        let context = try makeContext()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = dueAt.addingTimeInterval(-30 * 60)
        let endAt = startAt.addingTimeInterval(90 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { dueAt })
        let parent = TaskItem(
            title: "daily deep work",
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)

        try repo.markDone(parent)

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        let expectedDelta = 24 * 60 * 60.0
        #expect(spawn?.dueAt == dueAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.startAt == startAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.endAt == endAt.addingTimeInterval(expectedDelta))
    }

    @MainActor
    @Test("markDone on recurring task without dueAt shifts start/end from completion anchor")
    func markDoneRecurringWithoutDueAtShiftsStartEndFromCompletionAnchor() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = stamp.addingTimeInterval(-30 * 60)
        let endAt = startAt.addingTimeInterval(90 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(
            title: "floating daily deep work",
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)

        try repo.markDone(parent)

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        let expectedDelta = 24 * 60 * 60.0
        #expect(spawn?.dueAt == stamp.addingTimeInterval(expectedDelta))
        #expect(spawn?.startAt == startAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.endAt == endAt.addingTimeInterval(expectedDelta))
    }

    @MainActor
    @Test("markDone on recurring task without endAt keeps spawn endAt nil")
    func markDoneRecurringWithoutEndKeepsSpawnEndNil() throws {
        let context = try makeContext()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = dueAt.addingTimeInterval(-45 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { dueAt })
        let parent = TaskItem(
            title: "daily open block",
            dueAt: dueAt,
            startAt: startAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)

        try repo.markDone(parent)

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        let expectedDelta = 24 * 60 * 60.0
        #expect(spawn?.startAt == startAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.endAt == nil)
    }

    @MainActor
    @Test("reopen on already-open task is no-op")
    func reopenIdempotentOpen() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let task = TaskItem(title: "x")
        try repo.insert(task)
        let originalUpdatedAt = task.updatedAt

        try repo.reopen(task)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
        #expect(task.updatedAt == originalUpdatedAt)
    }

    @MainActor
    @Test("update changing recurrenceRule regenerates spawn on done parent")
    func updateRegeneratesSpawnOnDoneParent() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let parent = TaskItem(title: "p", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        try repo.markDone(parent)

        let beforeChange = try context.fetch(FetchDescriptor<TaskItem>())
        let dailySpawnDue = beforeChange.first { $0.id != parent.id }?.dueAt
        #expect(dailySpawnDue != nil)

        try repo.update(parent) { $0.recurrenceRule = "FREQ=WEEKLY" }

        let after = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(after.count == 2)
        let weeklySpawn = after.first { $0.id != parent.id && $0.recurrenceRule == "FREQ=WEEKLY" }
        #expect(weeklySpawn != nil)
        #expect(weeklySpawn?.dueAt != dailySpawnDue)
    }

    @MainActor
    @Test("update changing recurrenceRule on done parent regenerates spawn preserving parent duration")
    func updateRegeneratesSpawnPreservingParentDuration() throws {
        let context = try makeContext()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = dueAt.addingTimeInterval(-15 * 60)
        let endAt = startAt.addingTimeInterval(90 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { dueAt })
        let parent = TaskItem(
            title: "p",
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)
        try repo.markDone(parent)

        try repo.update(parent) { $0.recurrenceRule = "FREQ=WEEKLY" }

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        let expectedDelta = 7 * 24 * 60 * 60.0
        #expect(spawn?.recurrenceRule == "FREQ=WEEKLY")
        #expect(spawn?.dueAt == dueAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.startAt == startAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.endAt == endAt.addingTimeInterval(expectedDelta))
    }

    @MainActor
    @Test("update changing recurrenceRule on done parent without dueAt shifts regenerated start/end")
    func updateRegeneratesSpawnWithoutDueAtShiftingStartEnd() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = stamp.addingTimeInterval(-15 * 60)
        let endAt = startAt.addingTimeInterval(90 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(
            title: "floating block",
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)
        try repo.markDone(parent)

        try repo.update(parent) { $0.recurrenceRule = "FREQ=WEEKLY" }

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        let expectedDelta = 7 * 24 * 60 * 60.0
        #expect(spawn?.recurrenceRule == "FREQ=WEEKLY")
        #expect(spawn?.dueAt == stamp.addingTimeInterval(expectedDelta))
        #expect(spawn?.startAt == startAt.addingTimeInterval(expectedDelta))
        #expect(spawn?.endAt == endAt.addingTimeInterval(expectedDelta))
    }

    @MainActor
    @Test("update changing recurrenceRule on open parent does not regenerate")
    func updateNoRegenerateOnOpenParent() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let task = TaskItem(title: "p", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(task)

        try repo.update(task) { $0.recurrenceRule = "FREQ=WEEKLY" }

        let stored = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.count == 1)
        #expect(task.recurrenceRule == "FREQ=WEEKLY")
    }

    @MainActor
    @Test("update clearing recurrenceRule removes spawn without insert")
    func updateClearingRuleRemovesSpawn() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let parent = TaskItem(title: "p", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        try repo.markDone(parent)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)

        try repo.update(parent) { $0.recurrenceRule = nil }

        let after = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(after.count == 1)
        #expect(parent.recurrenceRule == nil)
    }

    @MainActor
    @Test("update to exhausted-COUNT rule removes spawn without insert")
    func updateToExhaustedRuleRemovesSpawn() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let parent = TaskItem(title: "p", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        try repo.markDone(parent)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)

        try repo.update(parent) { $0.recurrenceRule = "FREQ=DAILY;COUNT=1" }

        let after = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(after.count == 1)
    }

    @MainActor
    @Test("update without rule change does not regenerate spawn")
    func updateUnchangedRuleNoRegenerate() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let parent = TaskItem(title: "p", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        try repo.markDone(parent)
        let spawnsBefore = try context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.id != parent.id }
            .map(\.id)

        try repo.update(parent) { $0.title = "renamed" }

        let spawnsAfter = try context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.id != parent.id }
            .map(\.id)
        #expect(spawnsAfter == spawnsBefore)
    }

    @MainActor
    @Test("update changing rule with title edit propagates new title to spawn")
    func updateRuleAndTitleTogetherPropagatesToSpawn() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let parent = TaskItem(title: "old", dueAt: now, recurrenceRule: "FREQ=DAILY")
        try repo.insert(parent)
        try repo.markDone(parent)

        try repo.update(parent) {
            $0.title = "new"
            $0.recurrenceRule = "FREQ=WEEKLY"
        }

        let spawn = try context.fetch(FetchDescriptor<TaskItem>())
            .first { $0.id != parent.id }
        #expect(spawn?.title == "new")
        #expect(spawn?.recurrenceRule == "FREQ=WEEKLY")
    }

    @MainActor
    @Test("update changing rule with title edit preserves duration on regenerated spawn")
    func updateRuleWithDurationPreservedThroughTitleChange() throws {
        let context = try makeContext()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = dueAt.addingTimeInterval(-30 * 60)
        let endAt = startAt.addingTimeInterval(60 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { dueAt })
        let parent = TaskItem(
            title: "old",
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)
        try repo.markDone(parent)

        try repo.update(parent) {
            $0.title = "new"
            $0.recurrenceRule = "FREQ=WEEKLY"
        }

        let spawn = try #require(
            try context.fetch(FetchDescriptor<TaskItem>())
                .first { $0.id != parent.id }
        )
        let spawnStartAt = try #require(spawn.startAt)
        let spawnEndAt = try #require(spawn.endAt)
        #expect(spawn.title == "new")
        #expect(spawn.recurrenceRule == "FREQ=WEEKLY")
        #expect(spawnEndAt.timeIntervalSince(spawnStartAt) == 3600)
    }

    @MainActor
    @Test("update clearing endAt does not regenerate spawn")
    func updateClearingEndAtNoSpawnRegen() throws {
        let context = try makeContext()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = dueAt.addingTimeInterval(-30 * 60)
        let endAt = startAt.addingTimeInterval(60 * 60)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { dueAt })
        let parent = TaskItem(
            title: "daily deep work",
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            recurrenceRule: "FREQ=DAILY"
        )
        try repo.insert(parent)
        try repo.markDone(parent)
        let spawnIdsBefore = Set(
            try context.fetch(FetchDescriptor<TaskItem>())
                .filter { $0.id != parent.id }
                .map(\.id)
        )

        try repo.update(parent) { $0.endAt = nil }

        let spawnIdsAfter = Set(
            try context.fetch(FetchDescriptor<TaskItem>())
                .filter { $0.id != parent.id }
                .map(\.id)
        )
        #expect(parent.endAt == nil)
        #expect(spawnIdsAfter == spawnIdsBefore)
    }
}
