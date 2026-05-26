import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("DueChipFormatter")
struct DueChipFormatterTests {
    let now = ISO8601DateFormatter().date(from: "2026-05-04T12:00:00Z")!
    var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .gmt
        return cal
    }

    @Test("nil dueAt yields .noDate")
    func noDate() {
        let task = TaskItem(title: "x", dueAt: nil)
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .noDate)
    }

    @Test("dueAt earlier than today reports days late")
    func overdue() {
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let task = TaskItem(title: "x", dueAt: calendar.startOfDay(for: twoDaysAgo))
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .overdue(daysLate: 2))
    }

    @Test("dueAt within today and no startAt yields .today(timeOfDay: nil)")
    func todayAllDay() {
        let task = TaskItem(title: "x", dueAt: calendar.startOfDay(for: now))
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .today(timeOfDay: nil))
    }

    @Test("dueAt today with startAt yields formatted time")
    func todayWithTime() {
        let day = calendar.startOfDay(for: now)
        let startAt = calendar.date(byAdding: .hour, value: 15, to: day)!
        let task = TaskItem(title: "x", dueAt: day, startAt: startAt)
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .today(timeOfDay: "15:00"))
    }

    @Test("dueAt tomorrow yields .tomorrow")
    func tomorrow() {
        let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let task = TaskItem(title: "x", dueAt: day)
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .tomorrow(timeOfDay: nil))
    }

    @Test("dueAt 5 days out yields .future with weekday + date")
    func future() {
        let day = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: now))!
        let task = TaskItem(title: "x", dueAt: day)
        let label = DueChipFormatter.label(for: task, now: now, calendar: calendar)
        #expect(label == .future(date: "9 May", timeOfDay: nil))
    }
}
