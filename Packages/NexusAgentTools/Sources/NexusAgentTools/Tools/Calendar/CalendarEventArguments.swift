import Foundation
import NexusCore

/// Parsed fields for a `calendar.events.create` / `update` draft (spec §9 / §12).
struct CalendarEventDraftFields {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarID: String?
}

/// Argument parsing for the `calendar.events.*` tools, reusing the schedule
/// formatter for ISO8601. Attendees are accepted but ignored on write (EventKit
/// cannot write attendees — see `EventDraft.attendees`).
enum CalendarEventArguments {
    static func parseDraft(_ args: JSONValue) throws -> CalendarEventDraftFields {
        let title = try TasksStructuredCreateArguments.trimmedRequiredString(args["title"], field: "title")
        let start = try requiredDate(args["start"], field: "start")
        let end = try requiredDate(args["end"], field: "end")
        guard end > start else {
            throw AgentError.validation("end must be after start")
        }
        let isAllDay = args["is_all_day"]?.boolValue ?? false
        let location = try TasksStructuredCreateArguments.optionalString(args["location"], field: "location")
        let calendarID = try TasksStructuredCreateArguments.optionalString(
            args["calendar_id"], field: "calendar_id"
        )
        return CalendarEventDraftFields(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: location,
            calendarID: calendarID
        )
    }

    static func requiredDate(_ value: JSONValue?, field: String) throws -> Date {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required ISO8601 field: \(field)")
        }
        guard let date = ScheduleDTOFormatter.date(text) else {
            throw AgentError.validation("Invalid ISO8601 timestamp for field: \(field)")
        }
        return date
    }

    static func optionalDate(_ value: JSONValue?, field: String) throws -> Date? {
        guard let value else { return nil }
        guard let text = value.stringValue, let date = ScheduleDTOFormatter.date(text) else {
            throw AgentError.validation("Invalid ISO8601 timestamp for field: \(field)")
        }
        return date
    }
}

/// Shared input-schema fragments for the create / update event tools.
enum CalendarEventSchema {
    static func draftProperties(titleRequired: Bool) -> [String: JSONSchema] {
        [
            "title": .string(description: "Event title."),
            "start": .string(description: "ISO8601 start timestamp."),
            "end": .string(description: "ISO8601 end timestamp."),
            "is_all_day": .boolean(description: "Whether the event is all-day (default false)."),
            "location": .string(description: "Optional location."),
            "calendar_id": .string(
                description: "Target writable calendar id. Omit to use the \"Nexus\" calendar."
            ),
        ]
    }
}
