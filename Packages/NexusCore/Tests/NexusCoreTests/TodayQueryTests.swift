import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TodayQuery")
struct TodayQueryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = hour
        return Calendar.gregorianUTC.date(from: comps)!
    }

    @MainActor
    @Test("overdue today and noDate buckets filter correctly")
    func buckets() throws {
        let context = try makeContext()
        let now = date(2026, 5, 4, hour: 14)
        context.insert(TaskItem(title: "y", dueAt: date(2026, 5, 3)))
        context.insert(TaskItem(title: "t", dueAt: date(2026, 5, 4)))
        context.insert(TaskItem(title: "tm", dueAt: date(2026, 5, 5)))
        context.insert(TaskItem(title: "n"))
        try context.save()

        let query = TodayQuery(calendar: .gregorianUTC)
        #expect(try query.overdue(now: now).apply(in: context).map(\.title) == ["y"])
        #expect(try query.today(now: now).apply(in: context).map(\.title) == ["t"])
        #expect(try query.noDate().apply(in: context).map(\.title) == ["n"])
    }

    @MainActor
    @Test("buckets exclude done snoozed and tombstoned")
    func excludesNonOpen() throws {
        let context = try makeContext()
        let now = date(2026, 5, 4)
        let done = TaskItem(title: "done", dueAt: date(2026, 5, 3))
        done.statusRaw = TaskStatus.done.rawValue
        let snoozed = TaskItem(title: "snoozed", dueAt: date(2026, 5, 3))
        snoozed.statusRaw = TaskStatus.snoozed.rawValue
        let deleted = TaskItem(title: "deleted", dueAt: date(2026, 5, 3))
        deleted.deletedAt = .now
        context.insert(done)
        context.insert(snoozed)
        context.insert(deleted)
        try context.save()

        #expect(try TodayQuery(calendar: .gregorianUTC).overdue(now: now).apply(in: context).isEmpty)
    }

    @MainActor
    @Test("awaiting returns open tasks blocking open targets")
    func awaiting_returnsOpenTasksBlockingOpenTargets() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.map(\.task.title) == ["blocker"])
        #expect(entries.map(\.blockedCount) == [1])
    }

    @MainActor
    @Test("awaiting excludes done blockers")
    func awaiting_excludesDoneBlockers() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        blocker.statusRaw = TaskStatus.done.rawValue
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.isEmpty)
    }

    @MainActor
    @Test("awaiting excludes links to done targets")
    func awaiting_excludesLinksToDoneTargets() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        blocked.statusRaw = TaskStatus.done.rawValue
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.isEmpty)
    }

    @MainActor
    @Test("awaiting excludes non-task block targets with matching task IDs")
    func awaiting_excludesNonTaskTargetsWithMatchingTaskIDs() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.note, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.isEmpty)
    }

    @MainActor
    @Test("awaiting counts duplicate block links to the same target once")
    func awaiting_countsDuplicateBlockLinksToSameTargetOnce() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        context.insert(blocker)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)
        try repo.create(from: (.task, blocker.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.map(\.task.title) == ["blocker"])
        #expect(entries.map(\.blockedCount) == [1])
    }

    @MainActor
    @Test("awaiting sorts by open blocked count descending")
    func awaiting_sortsByOpenBlockedCountDesc() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let big = TaskItem(title: "big")
        let small = TaskItem(title: "small")
        let t1 = TaskItem(title: "t1")
        let t2 = TaskItem(title: "t2")
        let t3 = TaskItem(title: "t3")
        for task in [big, small, t1, t2, t3] {
            context.insert(task)
        }
        try context.save()
        try repo.create(from: (.task, big.id), to: (.task, t1.id), linkKind: .blocks)
        try repo.create(from: (.task, big.id), to: (.task, t2.id), linkKind: .blocks)
        try repo.create(from: (.task, big.id), to: (.task, t3.id), linkKind: .blocks)
        try repo.create(from: (.task, small.id), to: (.task, t1.id), linkKind: .blocks)

        let entries = try TodayQuery().awaiting(now: .now, modelContext: context, linkRepository: repo)

        #expect(entries.map(\.task.title) == ["big", "small"])
        #expect(entries.map(\.blockedCount) == [3, 1])
    }

    @MainActor
    @Test("awaiting sort fallback by dueAt ascending")
    func awaiting_sortFallbackByDueAtAsc() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let earlier = TaskItem(title: "earlier", dueAt: date(2026, 5, 8))
        let later = TaskItem(title: "later", dueAt: date(2026, 5, 10))
        let blocked = TaskItem(title: "blocked")
        context.insert(earlier)
        context.insert(later)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, later.id), to: (.task, blocked.id), linkKind: .blocks)
        try repo.create(from: (.task, earlier.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery(calendar: .gregorianUTC).awaiting(
            now: date(2026, 5, 7),
            modelContext: context,
            linkRepository: repo
        )

        #expect(entries.map(\.task.title) == ["earlier", "later"])
        #expect(entries.map(\.blockedCount) == [1, 1])
    }

    @MainActor
    @Test("awaiting sort fallback places due dates before nil due dates")
    func awaiting_sortFallbackPlacesDueDatesBeforeNilDueDates() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let dated = TaskItem(title: "dated", dueAt: date(2026, 5, 8))
        let noDate = TaskItem(title: "no date")
        let blocked = TaskItem(title: "blocked")
        context.insert(dated)
        context.insert(noDate)
        context.insert(blocked)
        try context.save()
        try repo.create(from: (.task, noDate.id), to: (.task, blocked.id), linkKind: .blocks)
        try repo.create(from: (.task, dated.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery(calendar: .gregorianUTC).awaiting(
            now: date(2026, 5, 7),
            modelContext: context,
            linkRepository: repo
        )

        #expect(entries.map(\.task.title) == ["dated", "no date"])
        #expect(entries.map(\.blockedCount) == [1, 1])
    }

    @MainActor
    @Test("buckets exclude tasks owned by archived projects when ids provided")
    func excludesTasksFromArchivedProjects() throws {
        let context = try makeContext()
        let now = date(2026, 5, 4)
        let archivedProjectID = UUID()
        let activeProjectID = UUID()

        let archivedOverdue = TaskItem(
            title: "archived overdue",
            dueAt: date(2026, 5, 3),
            projectID: archivedProjectID
        )
        let activeOverdue = TaskItem(
            title: "active overdue",
            dueAt: date(2026, 5, 3),
            projectID: activeProjectID
        )
        let archivedToday = TaskItem(
            title: "archived today",
            dueAt: date(2026, 5, 4),
            projectID: archivedProjectID
        )
        let activeToday = TaskItem(
            title: "active today",
            dueAt: date(2026, 5, 4),
            projectID: activeProjectID
        )
        let archivedNoDate = TaskItem(title: "archived no date", projectID: archivedProjectID)
        let activeNoDate = TaskItem(title: "active no date", projectID: activeProjectID)
        let orphanNoDate = TaskItem(title: "orphan no date")

        let allTasks = [
            archivedOverdue, activeOverdue,
            archivedToday, activeToday,
            archivedNoDate, activeNoDate, orphanNoDate,
        ]
        for task in allTasks {
            context.insert(task)
        }
        try context.save()

        let query = TodayQuery(calendar: .gregorianUTC)
        let excluded: Set<UUID> = [archivedProjectID]

        #expect(
            try query.overdue(now: now, excludingProjectIDs: excluded)
                .apply(in: context).map(\.title) == ["active overdue"]
        )
        #expect(
            try query.today(now: now, excludingProjectIDs: excluded)
                .apply(in: context).map(\.title) == ["active today"]
        )
        let noDateTitles = try query.noDate(excludingProjectIDs: excluded)
            .apply(in: context).map(\.title).sorted()
        #expect(noDateTitles == ["active no date", "orphan no date"])

        // Sanity check: without the exclusion the archived rows surface again.
        #expect(try query.overdue(now: now).apply(in: context).count == 2)
    }
}
