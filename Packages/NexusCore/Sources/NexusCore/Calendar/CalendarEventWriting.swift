import Foundation

/// A Sendable description of an event to create or update (spec §8 / §9). Kept
/// EventKit-free so the `CalendarSyncReconciler` is fully testable against a fake
/// writer; the `EventKitCalendarProvider` maps this onto `EKEvent`.
///
/// `recurrence` reuses the existing `RRule` (spec §9 — the future event editor's
/// recurrence comes through here). The scheduler's mirror events are always
/// single (`recurrence == nil`); recurrence is a provider capability for the
/// event editor, not something the reconciler exercises (spec §8).
public struct EventDraft: Equatable, Sendable {
    /// Identifier of the target writable calendar (e.g. the "Nexus" calendar).
    /// `nil` means "no system-calendar event": on create the write is skipped
    /// entirely (no EKEvent saved), and on update the event's current calendar is
    /// left unchanged (#7).
    public var calendarID: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// Attendee email addresses. NOTE: EventKit's public API exposes
    /// `EKEvent.attendees` read-only — the `EventKitCalendarProvider` cannot
    /// *write* attendees (private KVC is an App Store rejection risk and is not
    /// used). This field is retained for read-side round-tripping and as a
    /// forward-looking contract; writes ignore it.
    public var attendees: [String]
    public var recurrence: RRule?
    /// Alarm offsets in seconds relative to the event start (negative = before).
    public var alarmOffsets: [TimeInterval]

    public init(
        calendarID: String?,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        attendees: [String] = [],
        recurrence: RRule? = nil,
        alarmOffsets: [TimeInterval] = []
    ) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.attendees = attendees
        self.recurrence = recurrence
        self.alarmOffsets = alarmOffsets
    }
}

/// A Sendable snapshot of a calendar event read back from the store (spec §8).
/// Distinct from `CalendarEvent` (the read-side view shaped for the meeting/UI
/// surfaces): this carries the calendar identifier the reconciler diffs against.
public struct CalendarEventSnapshot: Equatable, Sendable {
    public var eventID: String
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date

    public init(eventID: String, calendarID: String, title: String, start: Date, end: Date) {
        self.eventID = eventID
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
    }
}

/// Which occurrences of a recurring event a write (update / delete) affects
/// (spec §9). Maps onto EventKit's two-case `EKSpan`; non-recurring events ignore
/// it. EventKit has NO "all events" span, so the editor offers only these two for
/// a recurring event (R2/R3).
public enum CalendarEventSpan: Sendable, Equatable {
    /// Only the single occurrence the identifier resolves to.
    case thisEvent
    /// This occurrence and every later one in the series.
    case futureEvents
}

/// Full event write surface (spec §8 / §9). Separate from `CalendarEventProviding`
/// (read-only, consumed widely by Meetings / Today / Watch) so adding writes never
/// breaks the existing read conformers. `EventKitCalendarProvider` conforms to both;
/// the `CalendarSyncReconciler` depends only on this protocol and is tested with a
/// fake.
///
/// EventKit-free by contract: every parameter and return type is a Sendable value
/// type. EventKit lives entirely inside the `EventKitCalendarProvider`
/// implementation.
public protocol CalendarEventWriting: Sendable {
    /// Sentinel identifier returned by `createEvent` when the draft's `calendarID`
    /// is `nil` and no system-calendar event was written (#7). Callers must treat
    /// it as "skipped", not a real event id.
    static var skippedEventID: String { get }

    /// Request full calendar access (write requires full access, not write-only).
    @discardableResult
    func requestFullAccess() async throws -> CalendarAuthorizationStatus

    /// Ensure the dedicated "Nexus" write-target calendar exists, creating it on
    /// demand (spec §13). Returns its calendar identifier.
    func ensureNexusCalendar() async throws -> String

    /// Create an event from a draft. Returns the new event identifier.
    @discardableResult
    func createEvent(_ draft: EventDraft) async throws -> String

    /// Update an existing event in place to match `draft`. `span` selects which
    /// occurrences a recurring event's change applies to (ignored when the event
    /// does not recur).
    func updateEvent(id: String, with draft: EventDraft, span: CalendarEventSpan) async throws

    /// Delete an event by identifier. A no-op if it no longer exists. `span`
    /// selects which occurrences of a recurring event are removed (ignored when
    /// the event does not recur) — `.thisEvent` deletes one occurrence,
    /// `.futureEvents` deletes this occurrence and all later ones.
    func deleteEvent(id: String, span: CalendarEventSpan) async throws

    /// Read events in a single calendar overlapping `[start, end)`. The reconciler
    /// diffs only the "Nexus" calendar — never the read-everything `eventsBetween`.
    func events(inCalendar calendarID: String, start: Date, end: Date) async throws -> [CalendarEventSnapshot]

    /// Look up a single event by identifier across ALL calendars, or nil if it no
    /// longer exists anywhere. Lets the reconciler distinguish a genuine deletion
    /// from a move to another calendar: a moved event leaves the window-scoped
    /// Nexus fetch but survives globally under the same identifier (R1). The
    /// returned snapshot's `calendarID` reflects the event's current calendar.
    func eventSnapshot(id: String) async throws -> CalendarEventSnapshot?
}

extension CalendarEventWriting {
    /// Shared sentinel value (see protocol requirement) so conformers needn't each
    /// redeclare it.
    public static var skippedEventID: String { "nexus.calendar.skipped" }

    /// `.thisEvent` is the right default for single mirror events (scheduler) and
    /// agent writes — only the user-facing editor passes an explicit span for a
    /// recurring event, so existing callers stay unchanged (R2/R3).
    public func updateEvent(id: String, with draft: EventDraft) async throws {
        try await updateEvent(id: id, with: draft, span: .thisEvent)
    }

    public func deleteEvent(id: String) async throws {
        try await deleteEvent(id: id, span: .thisEvent)
    }
}
