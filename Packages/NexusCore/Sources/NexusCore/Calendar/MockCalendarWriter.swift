import Foundation

/// In-memory `CalendarEventWriting` + `CalendarListing` fake (spec §8 / §9). Used
/// by SwiftUI previews and by feature-package tests that exercise the event
/// editor / multi-cal Settings without EventKit. Mirrors
/// `MockCalendarEventProvider` (lock-guarded, `@unchecked Sendable`).
///
/// Not a substitute for the integration tests against the real
/// `EventKitCalendarProvider`; it models the contract, not EventKit semantics.
public final class MockCalendarWriter: CalendarEventWriting, CalendarListing, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 0
    private var events: [String: EventDraft] = [:]
    private var calendars: [CalendarInfo]
    private let nexusCalendarID: String

    public init(
        calendars: [CalendarInfo] = MockCalendarWriter.defaultCalendars,
        nexusCalendarID: String = "nexus-calendar"
    ) {
        self.calendars = calendars
        self.nexusCalendarID = nexusCalendarID
    }

    public static let defaultCalendars: [CalendarInfo] = [
        CalendarInfo(id: "personal", title: "Personal", sourceTitle: "iCloud", colorHex: "#3B82F6", isWritable: true),
        CalendarInfo(id: "work", title: "Work", sourceTitle: "iCloud", colorHex: "#F59E0B", isWritable: true),
        CalendarInfo(id: "holidays", title: "Holidays", sourceTitle: "Subscriptions", colorHex: "#10B981", isWritable: false),
    ]

    public func requestFullAccess() async throws -> CalendarAuthorizationStatus { .fullAccess }

    public func ensureNexusCalendar() async throws -> String {
        locked {
            if !calendars.contains(where: { $0.id == nexusCalendarID }) {
                calendars.append(
                    CalendarInfo(id: nexusCalendarID, title: "Nexus", sourceTitle: "iCloud", colorHex: "#8B5CF6", isWritable: true)
                )
            }
            return nexusCalendarID
        }
    }

    @discardableResult
    public func createEvent(_ draft: EventDraft) async throws -> String {
        locked {
            nextID += 1
            let id = "event-\(nextID)"
            events[id] = draft
            return id
        }
    }

    public func updateEvent(id: String, with draft: EventDraft, span: CalendarEventSpan) async throws {
        locked { events[id] = draft }
    }

    public func deleteEvent(id: String, span: CalendarEventSpan) async throws {
        locked { events[id] = nil }
    }

    public func eventSnapshot(id: String) async throws -> CalendarEventSnapshot? {
        locked {
            guard let draft = events[id] else { return nil }
            return CalendarEventSnapshot(
                eventID: id,
                calendarID: draft.calendarID,
                title: draft.title,
                start: draft.start,
                end: draft.end
            )
        }
    }

    public func events(inCalendar calendarID: String, start: Date, end: Date) async throws -> [CalendarEventSnapshot] {
        locked {
            events.compactMap { id, draft -> CalendarEventSnapshot? in
                guard draft.calendarID == calendarID, draft.end > start, draft.start < end else { return nil }
                return CalendarEventSnapshot(
                    eventID: id,
                    calendarID: calendarID,
                    title: draft.title,
                    start: draft.start,
                    end: draft.end
                )
            }
            .sorted { $0.start == $1.start ? $0.eventID < $1.eventID : $0.start < $1.start }
        }
    }

    public func availableCalendars() async throws -> [CalendarInfo] {
        locked { calendars }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
