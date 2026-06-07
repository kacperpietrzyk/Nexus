import Foundation
import Testing

@testable import NexusCore

@Suite("DayPlanCandidates")
struct DayPlanCandidatesTests {
    private let calendar = Calendar(identifier: .gregorian)
    // 2026-06-08 10:00 UTC (a fixed, deterministic "now").
    private let now = Date(timeIntervalSince1970: 1_780_653_600)

    private func task(
        title: String,
        due: Date? = nil,
        pinned: Bool = false,
        status: TaskStatus = .open,
        deleted: Bool = false
    ) -> TaskItem {
        let task = TaskItem(title: title, dueAt: due, pinnedAsFocus: pinned)
        task.statusRaw = status.rawValue
        if deleted { task.deletedAt = now }
        return task
    }

    @Test("Selects overdue, due-today, and pinned; excludes future and non-open")
    func selectsCorrectPool() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let laterToday = cal.date(byAdding: .hour, value: 4, to: now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!

        let overdue = task(title: "overdue", due: yesterday)
        let dueToday = task(title: "today", due: laterToday)
        let pinnedFuture = task(title: "pinned-future", due: tomorrow, pinned: true)
        let future = task(title: "future", due: tomorrow)
        let done = task(title: "done", due: laterToday, status: .done)
        let deleted = task(title: "deleted", due: laterToday, deleted: true)

        let result = DayPlanCandidates.select(
            from: [overdue, dueToday, pinnedFuture, future, done, deleted],
            now: now,
            calendar: cal
        )

        let titles = Set(result.map(\.title))
        #expect(titles == ["overdue", "today", "pinned-future"])
    }

    @Test("A pinned task with no due date is still a candidate")
    func pinnedNoDue() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let pinned = task(title: "pinned", pinned: true)
        let unpinnedNoDue = task(title: "floating")

        let result = DayPlanCandidates.select(from: [pinned, unpinnedNoDue], now: now, calendar: cal)
        #expect(result.map(\.title) == ["pinned"])
    }

    @Test("Deterministic: same input yields same output order")
    func deterministic() {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let a = task(title: "a", due: now)
        let b = task(title: "b", due: now)
        let first = DayPlanCandidates.select(from: [a, b], now: now, calendar: cal).map(\.title)
        let second = DayPlanCandidates.select(from: [a, b], now: now, calendar: cal).map(\.title)
        #expect(first == second)
    }
}
