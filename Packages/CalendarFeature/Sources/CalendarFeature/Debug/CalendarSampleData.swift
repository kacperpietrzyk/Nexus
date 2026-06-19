#if DEBUG
import Foundation
import NexusCore

// MARK: - Sample data

/// Deterministic fixture set used by the DEBUG sample provider and by test
/// corpora in later tasks. All dates are computed from a passed `anchor` so the
/// set is always relative to the requested window, never hardcoded to a specific
/// calendar date.
public enum CalendarSampleData {

    /// Returns a fixed-but-anchor-relative set of `CalendarEvent`s:
    ///
    /// - An all-day event spanning Tue→Thu of the anchor's week.
    /// - Two overlapping timed meetings (08:45–10:00 and 09:00–10:00) on anchor day.
    /// - A timed event with a physical location and an organizer.
    /// - A video-call meeting with an organizer and two attendees.
    /// - A couple of ordinary timed events on adjacent days.
    ///
    /// The events are keyed to `anchor`-week day boundaries, so they always
    /// fall inside the week window the grid requests.
    public static func events(around anchor: Date) -> [CalendarEvent] {
        let cal = Calendar.current
        let weekStart = startOfWeek(for: anchor, using: cal)
        guard
            let tue = cal.date(byAdding: .day, value: 1, to: weekStart),
            let wed = cal.date(byAdding: .day, value: 2, to: weekStart),
            let thu = cal.date(byAdding: .day, value: 3, to: weekStart),
            let fri = cal.date(byAdding: .day, value: 4, to: weekStart)
        else { return [] }
        let anchorDay = cal.startOfDay(for: anchor)
        return [
            allDaySprintEvent(tue: tue, thu: thu, cal: cal),
            overlapStandup(on: anchorDay, cal: cal),
            overlapProductSync(on: anchorDay, cal: cal),
            locatedArchReview(on: wed, cal: cal),
            locatedTeamLunch(on: fri, cal: cal),
            ordinary1on1(on: thu, cal: cal),
            ordinaryDeepWork(on: wed, cal: cal),
        ]
    }

    // MARK: - Individual event factories

    /// (a) All-day event spanning Tue → Thu.
    private static func allDaySprintEvent(tue: Date, thu: Date, cal: Calendar) -> CalendarEvent {
        let end = cal.date(byAdding: .day, value: 1, to: thu) ?? thu
        return CalendarEvent(
            id: "sample-allday-1",
            title: "Design Sprint",
            start: tue,
            end: end,
            calendarColorHex: "#5856D6",
            isAllDay: true,
            calendarID: "sample-work",
            organizer: Attendee(name: "Jordan Lee", email: "jordan@example.com", role: .chair)
        )
    }

    /// (b-1) Overlapping meeting on anchor day — starts 08:45.
    private static func overlapStandup(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-overlap-1",
            title: "Standup",
            start: time(on: day, hour: 8, minute: 45, cal: cal),
            end: time(on: day, hour: 10, minute: 0, cal: cal),
            isVideoCall: true,
            urlForJoin: URL(string: "https://meet.example.com/standup"),
            calendarColorHex: "#34C759",
            calendarID: "sample-work",
            organizer: Attendee(
                name: "Alex Kim",
                email: "alex@example.com",
                responseStatus: .accepted,
                role: .chair
            ),
            notes: "Daily sync — share blockers."
        )
    }

    /// (b-2) Overlapping meeting on anchor day — starts 09:00.
    private static func overlapProductSync(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-overlap-2",
            title: "Product Sync",
            start: time(on: day, hour: 9, minute: 0, cal: cal),
            end: time(on: day, hour: 10, minute: 0, cal: cal),
            isVideoCall: true,
            urlForJoin: URL(string: "https://meet.example.com/product"),
            calendarColorHex: "#FF9500",
            calendarID: "sample-work",
            organizer: Attendee(
                name: "Sam Torres",
                email: "sam@example.com",
                responseStatus: .accepted,
                role: .chair
            )
        )
    }

    /// (c-1) Located event with organizer on Wednesday.
    private static func locatedArchReview(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-located-1",
            title: "Architecture Review",
            start: time(on: day, hour: 14, minute: 0, cal: cal),
            end: time(on: day, hour: 15, minute: 30, cal: cal),
            location: "Room 4B, Main Campus",
            attendees: [
                Attendee(
                    name: "You",
                    email: "kacper@example.com",
                    responseStatus: .accepted,
                    role: .required,
                    isCurrentUser: true
                ),
                Attendee(
                    name: "Jordan Lee",
                    email: "jordan@example.com",
                    responseStatus: .accepted,
                    role: .optional
                ),
            ],
            calendarColorHex: "#007AFF",
            calendarID: "sample-work",
            organizer: Attendee(
                name: "Jordan Lee",
                email: "jordan@example.com",
                responseStatus: .accepted,
                role: .chair
            )
        )
    }

    /// (c-2) Located event with organizer on Friday.
    private static func locatedTeamLunch(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-located-2",
            title: "Team Lunch",
            start: time(on: day, hour: 12, minute: 30, cal: cal),
            end: time(on: day, hour: 13, minute: 30, cal: cal),
            location: "The Green Terrace, 2nd Floor",
            attendees: [
                Attendee(
                    name: "You",
                    email: "kacper@example.com",
                    responseStatus: .accepted,
                    role: .required,
                    isCurrentUser: true
                )
            ],
            calendarColorHex: "#FF2D55",
            calendarID: "sample-personal",
            organizer: Attendee(name: "Alex Kim", email: "alex@example.com", role: .chair)
        )
    }

    /// (d-1) Ordinary event on Thursday.
    private static func ordinary1on1(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-ordinary-1",
            title: "1:1 with Manager",
            start: time(on: day, hour: 11, minute: 0, cal: cal),
            end: time(on: day, hour: 11, minute: 30, cal: cal),
            isVideoCall: true,
            urlForJoin: URL(string: "https://meet.example.com/1on1"),
            calendarColorHex: "#30B0C7",
            calendarID: "sample-work"
        )
    }

    /// (d-2) Ordinary event on Wednesday.
    private static func ordinaryDeepWork(on day: Date, cal: Calendar) -> CalendarEvent {
        CalendarEvent(
            id: "sample-ordinary-2",
            title: "Deep Work Block",
            start: time(on: day, hour: 9, minute: 0, cal: cal),
            end: time(on: day, hour: 11, minute: 0, cal: cal),
            calendarColorHex: "#636366",
            calendarID: "sample-personal"
        )
    }

    // MARK: - Calendar helpers

    private static func startOfWeek(for date: Date, using cal: Calendar) -> Date {
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? cal.startOfDay(for: date)
    }

    private static func time(on base: Date, hour: Int, minute: Int, cal: Calendar) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
}

// MARK: - Private type alias for readability inside this file

private typealias Attendee = CalendarEvent.Attendee

// MARK: - DEBUG sample provider

/// A read-only `CalendarEventProviding` that vends `CalendarSampleData.events`
/// for the DEBUG configuration when calendar access has not been granted.
///
/// - `authorizationStatus()` returns `.notDetermined` so `hasCalendarAccess`
///   is false and the "Calendar access needed" banner still shows.
/// - `eventsBetween(start:end:)` filters the full sample set to the requested
///   window so navigation (previous/next week) works correctly: moving away from
///   the anchor week returns an empty grid rather than stale events, matching
///   what a real provider would do.
public struct CalendarSampleProvider: CalendarEventProviding {

    public init() {}

    public func authorizationStatus() -> CalendarAuthorizationStatus { .notDetermined }

    public func requestAccess() async throws -> CalendarAuthorizationStatus { .notDetermined }

    public func eventsToday(now: Date) async throws -> [CalendarEvent] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return try await eventsBetween(start: dayStart, end: dayEnd)
    }

    public func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        // Anchor the sample set to the week that contains `start` so the events
        // always fall inside the requested window on first load.
        CalendarSampleData.events(around: start).filter { event in
            event.end > start && event.start < end
        }
    }
}
#endif
