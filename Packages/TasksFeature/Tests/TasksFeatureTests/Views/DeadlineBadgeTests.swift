import Foundation
import NexusUI
import Testing

@testable import TasksFeature

@Suite("DeadlineBadgeFormatter")
struct DeadlineBadgeTests {
    let now = ISO8601DateFormatter().date(from: "2026-05-04T12:00:00Z")!
    var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .gmt
        return cal
    }

    @Test("nil deadline hides badge")
    func noDeadline() {
        let presentation = DeadlineBadgeFormatter.presentation(
            deadlineAt: nil,
            now: now,
            calendar: calendar
        )

        #expect(presentation == nil)
    }

    @Test("past deadline is marked missed with rose tone")
    func missedDeadline() {
        let deadline = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let presentation = DeadlineBadgeFormatter.presentation(
            deadlineAt: deadline,
            now: now,
            calendar: calendar
        )

        #expect(presentation == DeadlineBadgePresentation(label: "deadline missed", tone: .rose, kind: .missed))
    }

    @Test("same-day deadline is marked today with rose tone")
    func todayDeadline() {
        let presentation = DeadlineBadgeFormatter.presentation(
            deadlineAt: calendar.startOfDay(for: now),
            now: now,
            calendar: calendar
        )

        #expect(presentation == DeadlineBadgePresentation(label: "deadline today", tone: .rose, kind: .today))
    }

    @Test("deadlines one to three days out use neutral tone (MP-2 accent burn-down)")
    func nearFutureDeadline() {
        for days in 1...3 {
            let deadline = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            let presentation = DeadlineBadgeFormatter.presentation(
                deadlineAt: deadline,
                now: now,
                calendar: calendar
            )

            #expect(presentation == DeadlineBadgePresentation(label: "deadline in \(days)d", tone: .neutral, kind: .upcoming))
        }
    }

    @Test("deadlines after three days use muted neutral tone")
    func defaultFutureDeadline() {
        let deadline = calendar.date(byAdding: .day, value: 4, to: calendar.startOfDay(for: now))!
        let presentation = DeadlineBadgeFormatter.presentation(
            deadlineAt: deadline,
            now: now,
            calendar: calendar
        )

        #expect(presentation == DeadlineBadgePresentation(label: "deadline in 4d", tone: .neutral, kind: .upcoming))
    }
}
