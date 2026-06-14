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
            CalendarEvent(id: "e1", title: "Sync", start: day("2026-06-15T10:00:00Z"),
                          end: day("2026-06-15T11:00:00Z"), location: nil, attendees: [],
                          isVideoCall: false, urlForJoin: nil, calendarColorHex: nil,
                          isAllDay: false, calendarID: nil, organizer: nil, notes: nil, meetingID: nil),
        ]
        let capacity = CapacityModel(dailyCapacityMinutes: 240) // 4h
        let loads = analyzer.analyze(tasks: items, events: events, days: [d], capacity: capacity)
        #expect(loads.count == 1)
        // 120 + 200 task + 60 event = 380 > 240 capacity
        #expect(loads[0].scheduledMinutes == 380)
        #expect(loads[0].isOverloaded == true)
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
