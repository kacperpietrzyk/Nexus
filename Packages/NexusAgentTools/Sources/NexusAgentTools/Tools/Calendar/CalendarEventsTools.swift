import Foundation
import NexusCore

/// `calendar.events.list` (spec §9 / §12): read events overlapping `[start, end)`
/// across the granted read calendars (obstacles + the user's events). Read-only.
public struct CalendarEventsListTool: AgentTool {
    public let name = "calendar.events.list"
    public let description =
        "Lists calendar events overlapping a time window across the granted calendars. "
        + "Read-only."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "start": .string(description: "ISO8601 window start (inclusive)."),
            "end": .string(description: "ISO8601 window end (exclusive)."),
        ],
        required: ["start", "end"]
    )

    private let provider: any CalendarEventProviding

    public init(provider: any CalendarEventProviding) {
        self.provider = provider
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let start = try CalendarEventArguments.requiredDate(args["start"], field: "start")
        let end = try CalendarEventArguments.requiredDate(args["end"], field: "end")
        guard end > start else {
            throw AgentError.validation("end must be after start")
        }
        guard provider.authorizationStatus() == .fullAccess else {
            throw AgentError.validation("Calendar access not granted; grant access in Settings.")
        }
        let events = try await provider.eventsBetween(start: start, end: end)
        return try TasksToolJSON.encode(events.map(CalendarEventDTO.init(from:)))
    }
}

/// `calendar.events.create` (spec §9 / §12): create an event from a draft. Idempotent
/// per the existing `*Idempotent` convention: when no `calendar_id` is given the event
/// lands in the "Nexus" calendar, and a same-window event with an identical
/// `(title, start, end)` is reused instead of duplicated. Requires write access.
public struct CalendarEventsCreateTool: AgentTool {
    public let name = "calendar.events.create"
    public let description =
        "Creates a calendar event. Idempotent: an existing event in the target calendar "
        + "with the same title, start, and end is reused rather than duplicated. Defaults "
        + "to the configured write calendar (falling back to the dedicated \"Nexus\" "
        + "calendar) when no calendar_id is given; pass calendar_id \"none\" to skip writing "
        + "a system-calendar event. Requires calendar write access."
    public let inputSchema: JSONSchema = .object(
        properties: CalendarEventSchema.draftProperties(titleRequired: true),
        required: ["title", "start", "end"]
    )

    private let writer: any CalendarEventWriting
    private let preferencesStore: UserDefaultsCalendarPreferencesStore

    public init(
        writer: any CalendarEventWriting,
        preferencesStore: UserDefaultsCalendarPreferencesStore = UserDefaultsCalendarPreferencesStore()
    ) {
        self.writer = writer
        self.preferencesStore = preferencesStore
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let fields = try CalendarEventArguments.parseDraft(args)
        return try await CalendarToolErrors.mapping {
            // #7: "none" skips the system-calendar write entirely — no dedup probe,
            // no EKEvent, and a clear skipped result instead of a phantom event id.
            guard
                let calendarID = try await CalendarTargetResolver.resolve(
                    fields.calendarTarget, writer: writer, preferencesStore: preferencesStore
                )
            else {
                _ = try await writer.createEvent(
                    EventDraft(
                        calendarID: nil,
                        title: fields.title,
                        start: fields.start,
                        end: fields.end,
                        isAllDay: fields.isAllDay,
                        location: fields.location,
                        attendees: fields.attendees,
                        recurrence: fields.recurrence,
                        alarmOffsets: fields.alarmOffsets
                    )
                )
                return .object([
                    "skipped": .bool(true),
                    "reason": .string("calendar_id was \"none\"; no system-calendar event written."),
                ])
            }

            // Dedup: an identical event already in the target calendar window is reused.
            let existing = try await writer.events(
                inCalendar: calendarID, start: fields.start, end: fields.end
            )
            if let match = existing.first(where: {
                $0.title == fields.title && $0.start == fields.start && $0.end == fields.end
            }) {
                return try TasksToolJSON.encode(CalendarEventDTO(from: match))
            }

            let draft = EventDraft(
                calendarID: calendarID,
                title: fields.title,
                start: fields.start,
                end: fields.end,
                isAllDay: fields.isAllDay,
                location: fields.location,
                attendees: fields.attendees,
                recurrence: fields.recurrence,
                alarmOffsets: fields.alarmOffsets
            )
            let eventID = try await writer.createEvent(draft)
            let dto = CalendarEventDTO(
                id: eventID,
                calendarID: calendarID,
                title: fields.title,
                start: ScheduleDTOFormatter.string(fields.start),
                end: ScheduleDTOFormatter.string(fields.end),
                isAllDay: fields.isAllDay,
                location: fields.location,
                attendees: fields.attendees
            )
            return try TasksToolJSON.encode(dto)
        }
    }
}

/// `calendar.events.update` (spec §9 / §12): update an existing event in place.
public struct CalendarEventsUpdateTool: AgentTool {
    public let name = "calendar.events.update"
    public let description =
        "Updates an existing calendar event in place to match the provided fields. "
        + "Requires calendar write access."
    public let inputSchema: JSONSchema = .object(
        properties: {
            var props = CalendarEventSchema.draftProperties(titleRequired: true)
            props["event_id"] = .string(description: "Event identifier to update.")
            return props
        }(),
        required: ["event_id", "title", "start", "end"]
    )

    private let writer: any CalendarEventWriting

    public init(writer: any CalendarEventWriting) {
        self.writer = writer
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let eventID = try TasksToolArguments.requiredString(args["event_id"], field: "event_id")
        let fields = try CalendarEventArguments.parseDraft(args)
        return try await CalendarToolErrors.mapping {
            // #7: an explicit calendar_id moves the event; omitted or "none" leaves
            // its current calendar in place (you can't un-calendar an existing event
            // without deleting it), so the draft carries nil and `apply` skips the
            // calendar reassignment.
            let calendarID: String?
            if case .explicit(let id) = fields.calendarTarget {
                calendarID = id
            } else {
                calendarID = nil
            }
            let draft = EventDraft(
                calendarID: calendarID,
                title: fields.title,
                start: fields.start,
                end: fields.end,
                isAllDay: fields.isAllDay,
                location: fields.location,
                attendees: fields.attendees,
                recurrence: fields.recurrence,
                alarmOffsets: fields.alarmOffsets
            )
            try await writer.updateEvent(id: eventID, with: draft)
            // Report the event's resulting calendar (the explicit target, or its
            // existing one read back) rather than a misleading nil.
            let resultingCalendarID: String?
            if let calendarID {
                resultingCalendarID = calendarID
            } else {
                let snapshot = try await writer.eventSnapshot(id: eventID)
                resultingCalendarID = snapshot?.calendarID
            }
            let dto = CalendarEventDTO(
                id: eventID,
                calendarID: resultingCalendarID,
                title: fields.title,
                start: ScheduleDTOFormatter.string(fields.start),
                end: ScheduleDTOFormatter.string(fields.end),
                isAllDay: fields.isAllDay,
                location: fields.location,
                attendees: fields.attendees
            )
            return try TasksToolJSON.encode(dto)
        }
    }
}

/// Resolves a parsed `CalendarTarget` into the concrete write calendar id for the
/// create path (#7): `.explicit` ⇒ that id; `.omitted` ⇒ the configured write
/// target, falling back to the on-demand "Nexus" calendar; `.none` ⇒ `nil`, the
/// signal to skip the system-calendar write.
@MainActor
enum CalendarTargetResolver {
    static func resolve(
        _ target: CalendarTarget,
        writer: any CalendarEventWriting,
        preferencesStore: UserDefaultsCalendarPreferencesStore
    ) async throws -> String? {
        switch target {
        case .none:
            return nil
        case .explicit(let id):
            return id
        case .omitted:
            if let configured = preferencesStore.load().writeCalendarID {
                return configured
            }
            return try await writer.ensureNexusCalendar()
        }
    }
}

/// `calendar.events.delete` (spec §9 / §12): delete an event by id. No-op if absent.
public struct CalendarEventsDeleteTool: AgentTool {
    public let name = "calendar.events.delete"
    public let description =
        "Deletes a calendar event by identifier. A no-op if the event no longer exists. "
        + "Requires calendar write access."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "event_id": .string(description: "Event identifier to delete.")
        ],
        required: ["event_id"]
    )

    private let writer: any CalendarEventWriting

    public init(writer: any CalendarEventWriting) {
        self.writer = writer
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let eventID = try TasksToolArguments.requiredString(args["event_id"], field: "event_id")
        try await CalendarToolErrors.mappingVoid {
            try await writer.deleteEvent(id: eventID)
        }
        return .object(["deleted": .bool(true), "event_id": .string(eventID)])
    }
}

/// Maps `CalendarProviderError` onto `AgentError` for the calendar tools (a denied
/// write surfaces as a validation error the agent can act on; everything else is an
/// internal error).
@MainActor
enum CalendarToolErrors {
    static func mapping(_ body: () async throws -> JSONValue) async throws -> JSONValue {
        do {
            return try await body()
        } catch let error as CalendarProviderError {
            throw map(error)
        }
    }

    static func mappingVoid(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as CalendarProviderError {
            throw map(error)
        }
    }

    private static func map(_ error: CalendarProviderError) -> AgentError {
        switch error {
        case .accessDenied:
            return .validation("Calendar write access denied; grant access in Settings.")
        case .underlying(let message):
            return .internalError("Calendar operation failed: \(message)")
        }
    }
}
