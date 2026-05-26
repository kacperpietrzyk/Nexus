import Foundation
import NexusCore
import Testing

@testable import NexusMeetings

@Test func correlatorReturnsNilWhenNoEventsInWindow() async throws {
    let provider = StubCalendarProvider(events: [])
    let correlator = CalendarCorrelator(provider: provider, window: 5 * 60)
    let result = await correlator.correlate(at: Date())
    #expect(result == nil)
}

@Test func correlatorPicksClosestStartingEvent() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let provider = StubCalendarProvider(events: [
        CalendarEvent(
            id: "far",
            title: "Far event",
            start: now.addingTimeInterval(600),
            end: now.addingTimeInterval(900)
        ),
        CalendarEvent(
            id: "close",
            title: "Close event",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(180)
        ),
    ])
    let correlator = CalendarCorrelator(provider: provider, window: 15 * 60)
    let result = await correlator.correlate(at: now)
    #expect(result?.eventID == "close")
    #expect(result?.title == "Close event")
}

@Test func correlatorPicksActiveEventBeforeCloserUpcomingEvent() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let provider = StubCalendarProvider(events: [
        CalendarEvent(
            id: "upcoming",
            title: "Upcoming",
            start: now.addingTimeInterval(5 * 60),
            end: now.addingTimeInterval(35 * 60)
        ),
        CalendarEvent(
            id: "active",
            title: "Active meeting",
            start: now.addingTimeInterval(-30 * 60),
            end: now.addingTimeInterval(30 * 60)
        ),
    ])
    let correlator = CalendarCorrelator(provider: provider, window: 15 * 60)
    let result = await correlator.correlate(at: now)
    #expect(result?.eventID == "active")
    #expect(result?.title == "Active meeting")
}

@Test func correlatorPrefersEarlierStartWhenStartDeltasTie() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let provider = StubCalendarProvider(events: [
        CalendarEvent(
            id: "future",
            title: "Future",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(120)
        ),
        CalendarEvent(
            id: "past",
            title: "Past",
            start: now.addingTimeInterval(-60),
            end: now
        ),
    ])
    let correlator = CalendarCorrelator(provider: provider, window: 5 * 60)
    let result = await correlator.correlate(at: now)
    #expect(result?.eventID == "past")
}

@Test func correlatorUsesTitleThenIDForDeterministicFinalTie() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let provider = StubCalendarProvider(events: [
        CalendarEvent(
            id: "z",
            title: "alpha",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(120)
        ),
        CalendarEvent(
            id: "b",
            title: "Beta",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(120)
        ),
        CalendarEvent(
            id: "a",
            title: "Alpha",
            start: now.addingTimeInterval(60),
            end: now.addingTimeInterval(120)
        ),
    ])
    let correlator = CalendarCorrelator(provider: provider, window: 5 * 60)
    let result = await correlator.correlate(at: now)
    #expect(result?.eventID == "a")
    #expect(result?.title == "Alpha")
}

@Test func correlatorReturnsNilWhenProviderThrows() async throws {
    let provider = ThrowingCalendarProvider()
    let correlator = CalendarCorrelator(provider: provider, window: 5 * 60)
    let result = await correlator.correlate(at: Date())
    #expect(result == nil)
}

private struct StubCalendarProvider: CalendarEventProviding {
    let events: [CalendarEvent]

    func authorizationStatus() -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        events
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        events.filter { event in
            event.end > start && event.start < end
        }
    }
}

private struct ThrowingCalendarProvider: CalendarEventProviding {
    func authorizationStatus() -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        throw CalendarProviderError.underlying("boom")
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        throw CalendarProviderError.underlying("boom")
    }
}
