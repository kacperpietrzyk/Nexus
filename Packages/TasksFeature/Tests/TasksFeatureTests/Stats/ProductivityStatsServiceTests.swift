import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("ProductivityStatsService")
struct ProductivityStatsServiceTests {
    @MainActor
    @Test("Daily counts include today and previous days only")
    func dailyCountMatchesCompletedTasks() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let outside = calendar.date(byAdding: .day, value: -7, to: now)!
        let todayTask = completedTask("today-1", at: now)
        let todaySecondTask = completedTask("today-2", at: now.addingTimeInterval(-600))
        let yesterdayTask = completedTask("yesterday", at: yesterday)
        let outsideTask = completedTask("outside", at: outside)

        [todayTask, todaySecondTask, yesterdayTask, outsideTask].forEach(context.insert)
        try context.save()

        let counts = try service.completedPerDay(last: 7, now: now)

        #expect(counts.count == 7)
        #expect(counts.first?.day == date(2026, 5, 4))
        #expect(counts.last?.day == date(2026, 5, 10))
        #expect(counts.first(where: { calendar.isDate($0.day, inSameDayAs: now) })?.count == 2)
        #expect(counts.first(where: { calendar.isDate($0.day, inSameDayAs: yesterday) })?.count == 1)
        #expect(counts.reduce(0) { $0 + $1.count } == 3)
    }

    @MainActor
    @Test("Daily counts exclude deleted open and missing completion stamps")
    func dailyCountsExcludeNonActiveCompletedRecords() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let live = completedTask("live", at: now)
        let deleted = completedTask("deleted", at: now)
        deleted.deletedAt = now
        let openWithCompletion = TaskItem(title: "open")
        openWithCompletion.lastCompletedAt = now
        let doneWithoutCompletion = TaskItem(title: "nil completion", status: .done)

        [live, deleted, openWithCompletion, doneWithoutCompletion].forEach(context.insert)
        try context.save()

        let counts = try service.completedPerDay(last: 1, now: now)

        #expect(counts.map(\.count) == [1])
    }

    @MainActor
    @Test("Current streak stops at the first recent day without completions")
    func currentStreakBreaksOnGap() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        [
            completedTask("today", at: now),
            completedTask("yesterday", at: yesterday),
            completedTask("three-days-ago", at: threeDaysAgo),
        ].forEach(context.insert)
        try context.save()

        #expect(try service.currentStreakDays(now: now) == 2)
    }

    @MainActor
    @Test("Per-project stats group sort and resolve active project names")
    func perProjectGroupsAndSortsByResolvedActiveProject() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let since = calendar.date(byAdding: .day, value: -7, to: now)!
        let alpha = Project(name: "Alpha")
        let zeta = Project(name: "Zeta")

        context.insert(alpha)
        context.insert(zeta)
        [
            completedTask("a1", at: now, projectID: alpha.id),
            completedTask("a2", at: now.addingTimeInterval(-60), projectID: alpha.id),
            completedTask("z1", at: now, projectID: zeta.id),
            completedTask("old", at: since.addingTimeInterval(-1), projectID: zeta.id),
        ].forEach(context.insert)
        try context.save()

        let stats = try service.completedPerProject(since: since)

        #expect(stats.map(\.projectName) == ["Alpha", "Zeta"])
        #expect(stats.map(\.completedCount) == [2, 1])
        #expect(stats.map(\.id) == [alpha.id, zeta.id])
    }

    @MainActor
    @Test("Per-project stats ignore nil missing deleted and archived projects")
    func perProjectIgnoresUnresolvableProjects() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let active = Project(name: "Active")
        let archived = Project(name: "Archived")
        archived.archivedAt = now
        let deleted = Project(name: "Deleted")
        deleted.deletedAt = now
        let missingProjectID = UUID()

        [active, archived, deleted].forEach(context.insert)
        [
            completedTask("active", at: now, projectID: active.id),
            completedTask("nil", at: now),
            completedTask("missing", at: now, projectID: missingProjectID),
            completedTask("archived", at: now, projectID: archived.id),
            completedTask("deleted", at: now, projectID: deleted.id),
        ].forEach(context.insert)
        try context.save()

        let stats = try service.completedPerProject(since: calendar.date(byAdding: .day, value: -1, to: now)!)

        #expect(stats.map(\.projectName) == ["Active"])
        #expect(stats.map(\.completedCount) == [1])
    }

    @MainActor
    @Test("Goal progress counts today + current week and clamps fractions")
    func goalProgressCountsTodayAndCurrentWeek() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let lastWeek = calendar.date(byAdding: .day, value: -14, to: now)!

        [
            completedTask("today-1", at: now),
            completedTask("today-2", at: now.addingTimeInterval(-600)),
            completedTask("out-of-week", at: lastWeek),
        ].forEach(context.insert)
        try context.save()

        let progress = try service.goalProgress(
            preferences: GoalsPreferences(dailyCompletionTarget: 2, weeklyCompletionTarget: 10),
            now: now
        )

        #expect(progress.dailyCompleted == 2)
        #expect(progress.weeklyCompleted == 2)
        #expect(progress.dailyTarget == 2)
        #expect(progress.weeklyTarget == 10)
        #expect(progress.dailyFraction == 1.0)  // clamped at 1 even when over
        #expect(progress.weeklyFraction == 0.2)
        #expect(progress.streakAtRisk == nil)  // already completed today
    }

    @MainActor
    @Test("Goal progress flags the streak at risk when today is still at zero")
    func goalProgressStreakAtRisk() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: now)!

        [completedTask("y", at: yesterday), completedTask("db", at: dayBefore)].forEach(context.insert)
        try context.save()

        let progress = try service.goalProgress(preferences: .default, now: now)

        #expect(progress.dailyCompleted == 0)
        #expect(progress.streakAtRisk == 2)
    }

    @MainActor
    @Test("Disabled daily goal never flags a streak at risk, even with real streak history")
    func goalProgressDisabledDailyTargetSuppressesStreakAtRisk() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)
        let now = date(2026, 5, 10, 15)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: now)!

        // Same history as goalProgressStreakAtRisk — only the target differs.
        [completedTask("y", at: yesterday), completedTask("db", at: dayBefore)].forEach(context.insert)
        try context.save()

        let progress = try service.goalProgress(
            preferences: GoalsPreferences(dailyCompletionTarget: 0, weeklyCompletionTarget: 10),
            now: now
        )

        #expect(progress.dailyCompleted == 0)
        #expect(progress.streakAtRisk == nil)  // daily goal off = streak protection off
    }

    @MainActor
    @Test("Goal progress with no history and zero targets is inert")
    func goalProgressZeroTargetsAndEmptyHistory() throws {
        let context = try makeContext()
        let service = ProductivityStatsService(context: context, calendar: calendar)

        let progress = try service.goalProgress(
            preferences: GoalsPreferences(dailyCompletionTarget: 0, weeklyCompletionTarget: 0),
            now: date(2026, 5, 10, 15)
        )

        #expect(progress.dailyFraction == 0)
        #expect(progress.weeklyFraction == 0)
        #expect(progress.streakAtRisk == nil)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func completedTask(_ title: String, at completedAt: Date, projectID: UUID? = nil) -> TaskItem {
        let task = TaskItem(title: title, status: .done, projectID: projectID)
        task.lastCompletedAt = completedAt
        return task
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        DateComponents(calendar: Self.calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day, hour: hour)
            .date!
    }

    private var calendar: Calendar { Self.calendar }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
}
