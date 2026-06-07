import Foundation
import Testing

@testable import NexusCore

@Suite("EveningShutdownSummary")
struct EveningShutdownSummaryTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // 2026-06-08 18:00 UTC
    private let now = Date(timeIntervalSince1970: 1_780_682_400)

    private func task(due: Date? = nil, completedAt: Date? = nil, status: TaskStatus) -> TaskItem {
        let task = TaskItem(title: "t", dueAt: due)
        task.statusRaw = status.rawValue
        task.lastCompletedAt = completedAt
        return task
    }

    @Test("Splits done-today from remaining due/overdue")
    func splits() {
        let cal = calendar
        let earlierToday = cal.date(byAdding: .hour, value: -3, to: now)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!

        let doneToday = task(completedAt: earlierToday, status: .done)
        let overdueOpen = task(due: yesterday, status: .open)
        let futureOpen = task(due: tomorrow, status: .open)

        let summary = EveningShutdownSummary.make(
            from: [doneToday, overdueOpen, futureOpen],
            now: now,
            calendar: cal
        )

        #expect(summary.completedTaskIDs == [doneToday.id])
        #expect(summary.remainingTaskIDs == [overdueOpen.id])
        #expect(!summary.isClear)
    }

    @Test("Clear when nothing due/overdue remains open")
    func clear() {
        let cal = calendar
        let earlierToday = cal.date(byAdding: .hour, value: -2, to: now)!
        let done = task(completedAt: earlierToday, status: .done)
        let summary = EveningShutdownSummary.make(from: [done], now: now, calendar: cal)
        #expect(summary.isClear)
        #expect(summary.completedCount == 1)
    }
}
