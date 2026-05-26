import Foundation

public final class MockCalendarEventProvider: CalendarEventProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: CalendarAuthorizationStatus
    private var _stubEvents: [CalendarEvent]
    private var _requestAccessHook: (@Sendable () -> CalendarAuthorizationStatus)?

    public var status: CalendarAuthorizationStatus {
        locked { _status }
    }

    public var stubEvents: [CalendarEvent] {
        locked { _stubEvents }
    }

    public var requestAccessHook: (@Sendable () -> CalendarAuthorizationStatus)? {
        get { locked { _requestAccessHook } }
        set { locked { _requestAccessHook = newValue } }
    }

    public init(
        status: CalendarAuthorizationStatus = .fullAccess,
        events: [CalendarEvent] = []
    ) {
        self._status = status
        self._stubEvents = events
    }

    public func setStatus(_ status: CalendarAuthorizationStatus) {
        locked { _status = status }
    }

    public func setEvents(_ events: [CalendarEvent]) {
        locked { _stubEvents = events }
    }

    public func authorizationStatus() -> CalendarAuthorizationStatus {
        status
    }

    public func requestAccess() async throws -> CalendarAuthorizationStatus {
        let hook = requestAccessHook
        if let hook {
            let newStatus = hook()
            setStatus(newStatus)
        }

        return status
    }

    public func eventsToday(now: Date) async throws -> [CalendarEvent] {
        guard status == .fullAccess else { return [] }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return try await eventsBetween(start: dayStart, end: dayEnd)
    }

    public func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        guard status == .fullAccess else { return [] }

        return stubEvents.filter { event in
            event.end > start && event.start < end
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
