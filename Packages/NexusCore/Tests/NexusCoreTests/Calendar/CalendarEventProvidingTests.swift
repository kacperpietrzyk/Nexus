import Foundation
import Testing

@testable import NexusCore

@Suite("CalendarEventProviding (Mock)")
struct CalendarEventProvidingTests {
    @Test("Returns events when fullAccess and within today's local day")
    func returnsToday() async throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 9)))
        let inside = CalendarEvent(
            id: "e1",
            title: "Standup",
            start: now.addingTimeInterval(900),
            end: now.addingTimeInterval(2_700)
        )
        let outside = CalendarEvent(
            id: "e2",
            title: "Tomorrow",
            start: now.addingTimeInterval(86_400),
            end: now.addingTimeInterval(90_000)
        )
        let provider = MockCalendarEventProvider(status: .fullAccess, events: [inside, outside])

        let events = try await provider.eventsToday(now: now)

        #expect(events == [inside])
    }

    @Test("Returns empty when access is denied")
    func emptyWhenDenied() async throws {
        let provider = MockCalendarEventProvider(
            status: .denied,
            events: [
                CalendarEvent(id: "x", title: "Denied", start: .now, end: .now.addingTimeInterval(3_600))
            ])

        let events = try await provider.eventsToday(now: .now)

        #expect(events.isEmpty)
    }

    @Test("requestAccess returns and stores hooked status")
    func requestAccessReturnsHookedStatus() async throws {
        let provider = MockCalendarEventProvider(status: .notDetermined)
        provider.requestAccessHook = { .fullAccess }

        let status = try await provider.requestAccess()

        #expect(status == .fullAccess)
        #expect(provider.authorizationStatus() == .fullAccess)
    }

    @Test("eventsBetween includes overlapping events and excludes events starting at upper boundary")
    func eventsBetweenUsesOverlapBoundaries() async throws {
        let start = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 10)))
        let end = start.addingTimeInterval(3_600)
        let atStart = CalendarEvent(id: "start", title: "Start", start: start, end: start.addingTimeInterval(900))
        let alreadyRunning = CalendarEvent(
            id: "already-running",
            title: "Already running",
            start: start.addingTimeInterval(-900),
            end: start.addingTimeInterval(900)
        )
        let beforeEnd = CalendarEvent(
            id: "before-end",
            title: "Before end",
            start: end.addingTimeInterval(-1),
            end: end.addingTimeInterval(900)
        )
        let endedAtStart = CalendarEvent(id: "ended", title: "Ended", start: start.addingTimeInterval(-900), end: start)
        let atEnd = CalendarEvent(id: "end", title: "End", start: end, end: end.addingTimeInterval(900))
        let provider = MockCalendarEventProvider(status: .fullAccess, events: [atStart, alreadyRunning, beforeEnd, endedAtStart, atEnd])

        let events = try await provider.eventsBetween(start: start, end: end)

        #expect(events == [atStart, alreadyRunning, beforeEnd])
    }
}
