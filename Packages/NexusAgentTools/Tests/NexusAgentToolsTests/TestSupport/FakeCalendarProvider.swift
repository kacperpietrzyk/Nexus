import Foundation
import NexusCore

/// Deterministic fake conforming to BOTH calendar protocols, for the schedule /
/// calendar agent-tool tests. Records writes and stubs reads — no EventKit. The
/// read side (`eventsBetween`) returns `stubEvents` filtered to the window; the
/// write side maintains an in-memory event store keyed by a monotonic id.
final class FakeCalendarProvider: CalendarEventProviding, CalendarEventWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: CalendarAuthorizationStatus
    private var _stubEvents: [CalendarEvent]
    private let nexusCalendarID: String
    private var nextSeq = 0
    private(set) var store: [String: CalendarEventSnapshot] = [:]

    private(set) var createdDrafts: [EventDraft] = []
    private(set) var updatedDrafts: [EventDraft] = []
    private(set) var updatedIDs: [String] = []
    private(set) var deletedIDs: [String] = []
    private(set) var ensureNexusCount = 0

    init(
        status: CalendarAuthorizationStatus = .fullAccess,
        stubEvents: [CalendarEvent] = [],
        nexusCalendarID: String = "nexus-cal"
    ) {
        self._status = status
        self._stubEvents = stubEvents
        self.nexusCalendarID = nexusCalendarID
    }

    func setStatus(_ status: CalendarAuthorizationStatus) { locked { _status = status } }

    // MARK: - CalendarEventProviding

    func authorizationStatus() -> CalendarAuthorizationStatus { locked { _status } }

    @discardableResult
    func requestAccess() async throws -> CalendarAuthorizationStatus { locked { _status } }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return try await eventsBetween(start: start, end: end)
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        guard authorizationStatus() == .fullAccess else { return [] }
        return locked { _stubEvents }.filter { $0.end > start && $0.start < end }
    }

    // MARK: - CalendarEventWriting

    @discardableResult
    func requestFullAccess() async throws -> CalendarAuthorizationStatus { locked { _status } }

    func ensureNexusCalendar() async throws -> String {
        locked {
            ensureNexusCount += 1
            return nexusCalendarID
        }
    }

    @discardableResult
    func createEvent(_ draft: EventDraft) async throws -> String {
        locked {
            nextSeq += 1
            let id = "evt-\(nextSeq)"
            createdDrafts.append(draft)
            store[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: draft.calendarID,
                title: draft.title,
                start: draft.start,
                end: draft.end
            )
            return id
        }
    }

    func updateEvent(id: String, with draft: EventDraft) async throws {
        locked {
            updatedDrafts.append(draft)
            updatedIDs.append(id)
            store[id] = CalendarEventSnapshot(
                eventID: id,
                calendarID: draft.calendarID,
                title: draft.title,
                start: draft.start,
                end: draft.end
            )
        }
    }

    func deleteEvent(id: String) async throws {
        locked {
            deletedIDs.append(id)
            store[id] = nil
        }
    }

    func events(inCalendar calendarID: String, start: Date, end: Date) async throws -> [CalendarEventSnapshot] {
        locked {
            store.values
                .filter { $0.calendarID == calendarID && $0.start < end && $0.end > start }
                .sorted { $0.eventID < $1.eventID }
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
