import Foundation
import NexusCore
import NexusUI
import Testing

@testable import TasksFeature

@Suite("TodayDashboard+Greeting v4")
struct TodayDashboardGreetingTests {
    @Test("greetingBlock builds")
    @MainActor
    func greetingBuilds() {
        let dashboard = TodayDashboard()
        _ = dashboard.greetingBlock(
            now: Date(timeIntervalSince1970: 1_778_571_720),
            workspaceName: "Test",
            meetingsCount: 3,
            tasksCount: 12,
            focusBlockTime: "14:00"
        )
    }

    @Test("dayProgress clamps before and after the 8-18 window")
    @MainActor
    func dayProgressClampsOutsideWorkday() throws {
        let dashboard = TodayDashboard()
        let morning = try makeDate(hour: 6, minute: 30)
        let evening = try makeDate(hour: 20, minute: 15)

        let before = dashboard.dayProgress(
            now: morning,
            items: [],
            doneCount: 3,
            totalCount: 12,
            focusedMinutes: 138
        )
        let after = dashboard.dayProgress(
            now: evening,
            items: [],
            doneCount: 3,
            totalCount: 12,
            focusedMinutes: 138
        )

        #expect(before.progress == 0)
        #expect(after.progress == 1)
        #expect(before.doneCount == 3)
        #expect(before.totalCount == 12)
        #expect(before.focusedMinutes == 138)
    }

    @Test("dayProgress maps in-window item starts to tick fractions")
    @MainActor
    func dayProgressMapsTickFractions() throws {
        let dashboard = TodayDashboard()
        let noon = try makeDate(hour: 12, minute: 0)
        let tenThirty = try makeDate(hour: 10, minute: 30)
        let beforeWindow = try makeDate(hour: 7, minute: 30)
        let afterWindow = try makeDate(hour: 19, minute: 0)

        let progress = dashboard.dayProgress(
            now: noon,
            items: [
                (start: beforeWindow, isDone: false),
                (start: tenThirty, isDone: true),
                (start: afterWindow, isDone: false),
            ],
            doneCount: 0,
            totalCount: 1,
            focusedMinutes: 0
        )

        #expect(progress.progress == 0.4)
        #expect(progress.tickFractions == [0.25])
    }

    @Test("timeOfDay branches by hour")
    @MainActor
    func timeOfDayBranchesByHour() throws {
        #expect(TodayDashboard.timeOfDay(try makeDate(hour: 2, minute: 0)) == .night)
        #expect(TodayDashboard.timeOfDay(try makeDate(hour: 8, minute: 0)) == .morning)
        #expect(TodayDashboard.timeOfDay(try makeDate(hour: 13, minute: 30)) == .afternoon)
        #expect(TodayDashboard.timeOfDay(try makeDate(hour: 19, minute: 0)) == .evening)
        #expect(TodayDashboard.timeOfDay(try makeDate(hour: 23, minute: 30)) == .night)
    }

    @Test("greetingPrefix maps each time-of-day to a Polish phrase")
    @MainActor
    func greetingPrefixPolish() throws {
        #expect(TodayDashboard.greetingPrefix(try makeDate(hour: 9, minute: 0)) == "Dzień dobry")
        #expect(TodayDashboard.greetingPrefix(try makeDate(hour: 14, minute: 0)) == "Dzień dobry")
        #expect(TodayDashboard.greetingPrefix(try makeDate(hour: 20, minute: 0)) == "Dobry wieczór")
        #expect(TodayDashboard.greetingPrefix(try makeDate(hour: 1, minute: 0)) == "Dobranoc")
    }

    @Test("focusBlockTime returns earliest future startAt")
    @MainActor
    func focusBlockTimeReturnsEarliestFutureStart() throws {
        let now = try makeDate(hour: 10, minute: 0)
        let past = try makeDate(hour: 8, minute: 30)
        let nearFuture = try makeDate(hour: 11, minute: 15)
        let farFuture = try makeDate(hour: 16, minute: 0)

        let pastTask = TaskItem(title: "Past")
        pastTask.startAt = past
        let nearTask = TaskItem(title: "Near")
        nearTask.startAt = nearFuture
        let farTask = TaskItem(title: "Far")
        farTask.startAt = farFuture

        let result = TodayDashboard.focusBlockTime(now: now, tasks: [pastTask, nearTask, farTask])
        #expect(result != nil)
        // We don't assert the exact format (locale-dependent), but we verify the hour & minute
        // tokens appear, ruling out the far-future and past starts.
        let needle1 = "11"
        let needle2 = "15"
        #expect(result?.contains(needle1) == true)
        #expect(result?.contains(needle2) == true)
    }

    @Test("focusBlockTime returns nil with no future tasks")
    @MainActor
    func focusBlockTimeReturnsNilWhenNothingScheduled() throws {
        let now = try makeDate(hour: 16, minute: 0)
        let past = try makeDate(hour: 9, minute: 0)
        let task = TaskItem(title: "Past")
        task.startAt = past
        let noStart = TaskItem(title: "No start")
        #expect(TodayDashboard.focusBlockTime(now: now, tasks: [task, noStart]) == nil)
    }

    @Test("resolvedWorkspaceName prefers stored value")
    @MainActor
    func resolvedWorkspaceNameStored() {
        #expect(TodayDashboard.resolvedWorkspaceName(stored: "Tomek") == "Tomek")
        #expect(TodayDashboard.resolvedWorkspaceName(stored: "  Anna  ") == "Anna")
    }

    @Test("resolvedWorkspaceName falls back when stored is empty or whitespace")
    @MainActor
    func resolvedWorkspaceNameFallback() {
        // We don't assert the exact fallback (it depends on the host OS/user) but it must be
        // non-empty.
        let fallback = TodayDashboard.resolvedWorkspaceName(stored: "")
        #expect(!fallback.isEmpty)
        let whitespaceFallback = TodayDashboard.resolvedWorkspaceName(stored: "   ")
        #expect(!whitespaceFallback.isEmpty)
    }

    @Test("dayProgressSummary aggregates done count, total, focused minutes, and tick fractions")
    @MainActor
    func dayProgressSummaryAggregates() throws {
        let now = try makeDate(hour: 10, minute: 0)
        let open = TaskItem(title: "Open")
        open.startAt = try makeDate(hour: 9, minute: 0)
        let done = TaskItem(title: "Done")
        done.startAt = try makeDate(hour: 11, minute: 0)
        done.endAt = try makeDate(hour: 12, minute: 0)
        done.statusRaw = "done"
        let invertedDuration = TaskItem(title: "Inverted")
        invertedDuration.startAt = try makeDate(hour: 15, minute: 0)
        invertedDuration.endAt = try makeDate(hour: 14, minute: 0)
        let noStart = TaskItem(title: "No start")

        let summary = TodayDashboard.dayProgressSummary(tasks: [open, done, invertedDuration, noStart])
        _ = now
        #expect(summary.doneCount == 1)
        #expect(summary.totalCount == 4)
        #expect(summary.focusedMinutes == 60)
        #expect(summary.progressItems.count == 3)
        #expect(summary.progressItems.contains { $0.isDone })
    }

    #if canImport(UIKit) && !os(watchOS)
    @Test("stripDeviceSuffix trims trailing iPhone/iPad markers")
    @MainActor
    func stripsDeviceSuffix() {
        #expect(TodayDashboard.stripDeviceSuffix("Kacper's iPhone") == "Kacper")
        #expect(TodayDashboard.stripDeviceSuffix("Anna iPad") == "Anna")
        #expect(TodayDashboard.stripDeviceSuffix("Solo") == "Solo")
    }
    #endif

    private func makeDate(hour: Int, minute: Int) throws -> Date {
        let calendar = Calendar.current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 5,
            day: 12,
            hour: hour,
            minute: minute
        )
        return try #require(components.date)
    }
}
