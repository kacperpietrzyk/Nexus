import Foundation
import Testing

@testable import NexusCore

@Suite struct WorkloadAnalyzerTests {
    private func day(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func sumsTaskAndEventMinutesPerDayAndFlagsOverload() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let analyzer = WorkloadAnalyzer(calendar: cal)
        let d = day("2026-06-15T00:00:00Z")
        let items = [
            ScheduledItem(id: UUID(), durationMinutes: 120, day: day("2026-06-15T09:00:00Z")),
            ScheduledItem(id: UUID(), durationMinutes: 200, day: day("2026-06-15T13:00:00Z")),
        ]
        let events = [
            CalendarEvent(
                id: "e1", title: "Sync", start: day("2026-06-15T10:00:00Z"),
                end: day("2026-06-15T11:00:00Z"), location: nil, attendees: [],
                isVideoCall: false, urlForJoin: nil, calendarColorHex: nil,
                isAllDay: false, calendarID: nil, organizer: nil, notes: nil, meetingID: nil)
        ]
        let capacity = CapacityModel(dailyCapacityMinutes: 240)  // 4h
        let loads = analyzer.analyze(tasks: items, events: events, days: [d], capacity: capacity)
        #expect(loads.count == 1)
        // 120 + 200 task + 60 event = 380 > 240 capacity
        #expect(loads[0].scheduledMinutes == 380)
        #expect(loads[0].isOverloaded == true)
    }

    @Test func multiDayEventIsClippedToEachDayBoundary() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let analyzer = WorkloadAnalyzer(calendar: cal)
        let d1 = day("2026-06-15T00:00:00Z")
        let d2 = day("2026-06-16T00:00:00Z")
        // A 30-hour event spanning two days: 22:00 day1 -> 04:00 day3-start. Each day
        // must only count the slice that falls inside it — not the full duration on
        // the start day (which fed a false "overloaded" signal).
        let events = [
            CalendarEvent(
                id: "multi", title: "Conference", start: day("2026-06-15T22:00:00Z"),
                end: day("2026-06-17T04:00:00Z"), location: nil, attendees: [],
                isVideoCall: false, urlForJoin: nil, calendarColorHex: nil,
                isAllDay: false, calendarID: nil, organizer: nil, notes: nil, meetingID: nil)
        ]
        let loads = analyzer.analyze(
            tasks: [], events: events, days: [d1, d2],
            capacity: CapacityModel(dailyCapacityMinutes: 480))
        // day1: 22:00 -> 24:00 = 2h = 120m (NOT the full 30h)
        #expect(loads[0].scheduledMinutes == 120)
        // day2: full 24h slice = 1440m (later-day slices must not vanish)
        #expect(loads[1].scheduledMinutes == 1440)
    }

    @Test func dayWithinCapacityIsNotOverloaded() {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = TimeZone(identifier: "UTC")!
        let analyzer = WorkloadAnalyzer(calendar: cal)
        let d = day("2026-06-15T00:00:00Z")
        let items = [ScheduledItem(id: UUID(), durationMinutes: 60, day: day("2026-06-15T09:00:00Z"))]
        let loads = analyzer.analyze(tasks: items, events: [], days: [d], capacity: CapacityModel(dailyCapacityMinutes: 240))
        #expect(loads[0].isOverloaded == false)
    }
}
