#if canImport(EventKit) && !os(watchOS)
@preconcurrency import EventKit
import Foundation

/// `CalendarEventWriting` conformance (spec §8 / §9): full event CRUD, the
/// on-demand "Nexus" calendar, a scoped per-calendar read, RRule mapping, and an
/// `EKEventStoreChanged` observer hook. EventKit stays isolated here; the
/// reconciler depends only on the protocol.
extension EventKitCalendarProvider: CalendarEventWriting, CalendarListing {
    @discardableResult
    public func requestFullAccess() async throws -> CalendarAuthorizationStatus {
        try await requestAccess()
    }

    public func ensureNexusCalendar() async throws -> String {
        try await onStore { store in
            if let existing = Self.nexusCalendar(in: store) {
                return existing.calendarIdentifier
            }

            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.nexusCalendarTitle
            guard let source = Self.writableSource(in: store) else {
                throw CalendarProviderError.underlying("No writable calendar source available")
            }
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
            } catch {
                throw CalendarProviderError.underlying(String(describing: error))
            }
            return calendar.calendarIdentifier
        }
    }

    @discardableResult
    public func createEvent(_ draft: EventDraft) async throws -> String {
        try await onStore { store in
            let event = EKEvent(eventStore: store)
            try Self.apply(draft, to: event, in: store)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw CalendarProviderError.underlying(String(describing: error))
            }
            guard let identifier = event.eventIdentifier else {
                throw CalendarProviderError.underlying("Saved event has no identifier")
            }
            return identifier
        }
    }

    public func updateEvent(id: String, with draft: EventDraft) async throws {
        try await onStore { store in
            guard let event = store.event(withIdentifier: id) else {
                throw CalendarProviderError.underlying("Event not found: \(id)")
            }
            try Self.apply(draft, to: event, in: store)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw CalendarProviderError.underlying(String(describing: error))
            }
        }
    }

    public func deleteEvent(id: String) async throws {
        try await onStore { store in
            // No-op if the event is already gone (idempotent delete, spec §14 cascade).
            guard let event = store.event(withIdentifier: id) else { return }
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw CalendarProviderError.underlying(String(describing: error))
            }
        }
    }

    public func events(inCalendar calendarID: String, start: Date, end: Date) async throws -> [CalendarEventSnapshot] {
        try await onStore { store in
            guard let calendar = store.calendar(withIdentifier: calendarID) else { return [] }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
            return store.events(matching: predicate).compactMap { event in
                guard let identifier = event.eventIdentifier else { return nil }
                return CalendarEventSnapshot(
                    eventID: identifier,
                    calendarID: calendarID,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate
                )
            }
            .sorted { $0.start == $1.start ? $0.eventID < $1.eventID : $0.start < $1.start }
        }
    }

    // MARK: - Calendar listing (spec §9 multi-cal Settings)

    public func availableCalendars() async throws -> [CalendarInfo] {
        guard authorizationStatus() == .fullAccess || authorizationStatus() == .writeOnly else { return [] }
        return try await onStore { store in
            store.calendars(for: .event)
                .map { calendar in
                    CalendarInfo(
                        id: calendar.calendarIdentifier,
                        title: calendar.title,
                        sourceTitle: calendar.source?.title ?? "",
                        colorHex: calendar.cgColor.flatMap(Self.hexString(from:)),
                        isWritable: calendar.allowsContentModifications
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.sourceTitle != rhs.sourceTitle {
                        return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
                    }
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
        }
    }

    // MARK: - EKEventStoreChanged observer

    /// Register `handler` to run whenever EventKit reports a store change
    /// (`.EKEventStoreChanged`). The composition root calls the reconciler's
    /// `reconcile(window:)` from the handler. Returns the observer token; the
    /// caller retains it for the observation's lifetime and removes it on teardown.
    public func observeStoreChanges(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: nil
        ) { _ in handler() }
    }

    // MARK: - Mapping

    static let nexusCalendarTitle = "Nexus"

    static func nexusCalendar(in store: EKEventStore) -> EKCalendar? {
        store.calendars(for: .event).first { $0.title == nexusCalendarTitle && $0.allowsContentModifications }
    }

    static func writableSource(in store: EKEventStore) -> EKSource? {
        // Prefer the default calendar's source (usually iCloud / the user's primary),
        // then any local source, then the first source that can hold event calendars.
        if let source = store.defaultCalendarForNewEvents?.source {
            return source
        }
        if let local = store.sources.first(where: { $0.sourceType == .local }) {
            return local
        }
        return store.sources.first { !$0.calendars(for: .event).isEmpty } ?? store.sources.first
    }

    static func apply(_ draft: EventDraft, to event: EKEvent, in store: EKEventStore) throws {
        guard let calendar = store.calendar(withIdentifier: draft.calendarID) else {
            throw CalendarProviderError.underlying("Calendar not found: \(draft.calendarID)")
        }
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location

        // NOTE: `draft.attendees` is intentionally NOT applied. `EKEvent.attendees`
        // is read-only in EventKit's public API — there is no supported way to set
        // attendees when creating/updating an event. The only path is private KVC,
        // which is an App Store rejection risk and is deliberately avoided. The
        // field is retained on `EventDraft` for read-side round-tripping (the event
        // editor can display existing attendees) and as a forward-looking contract;
        // writes silently ignore it. See the handoff "known limitations".

        // Replace recurrence (clear any prior rules first).
        event.recurrenceRules?.forEach(event.removeRecurrenceRule)
        if let rrule = draft.recurrence, let ekRule = ekRecurrenceRule(from: rrule) {
            event.addRecurrenceRule(ekRule)
        }

        // Replace alarms.
        event.alarms?.forEach(event.removeAlarm)
        for offset in draft.alarmOffsets {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
    }

    /// Map the Nexus `RRule` (RFC 5545 subset) onto an `EKRecurrenceRule`,
    /// reusing the existing model (spec §9).
    static func ekRecurrenceRule(from rrule: RRule) -> EKRecurrenceRule? {
        let frequency: EKRecurrenceFrequency
        switch rrule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        }

        let daysOfWeek: [EKRecurrenceDayOfWeek]? =
            rrule.byWeekday.isEmpty ? nil : rrule.byWeekday.map { EKRecurrenceDayOfWeek(ekWeekday(from: $0)) }
        let daysOfMonth: [NSNumber]? = rrule.byMonthDay.map { [NSNumber(value: $0)] }

        let end: EKRecurrenceEnd?
        if let count = rrule.count {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if let until = rrule.until {
            end = EKRecurrenceEnd(end: until)
        } else {
            end = nil
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, rrule.interval),
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    static func ekWeekday(from weekday: RRule.Weekday) -> EKWeekday {
        switch weekday {
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        case .sunday: return .sunday
        }
    }
}
#endif
