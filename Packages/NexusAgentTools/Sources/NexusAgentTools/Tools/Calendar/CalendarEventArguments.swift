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
    let attendees: [String]
    let recurrence: RRule?
    let alarmOffsets: [TimeInterval]
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
        let attendees = try optionalStringArray(args["attendees"], field: "attendees")
        let recurrence = try optionalRecurrenceRule(args["recurrence_rule"])
        let alarmOffsets = try optionalAlarmOffsets(args["alarm_offsets"])
        return CalendarEventDraftFields(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: location,
            calendarID: calendarID,
            attendees: attendees,
            recurrence: recurrence,
            alarmOffsets: alarmOffsets
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

    static func optionalRecurrenceRule(_ value: JSONValue?) throws -> RRule? {
        guard let value, value != .null else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("recurrence_rule must be a string")
        }
        do {
            return try RRuleParser.parse(text)
        } catch {
            throw AgentError.validation("recurrence_rule is not a valid RRULE: \(text)")
        }
    }

    static func optionalAlarmOffsets(_ value: JSONValue?) throws -> [TimeInterval] {
        guard let value, value != .null else { return [] }
        guard let values = value.arrayValue else {
            throw AgentError.validation("alarm_offsets must be an array")
        }
        return try values.map { element in
            guard let offset = element.doubleValue, offset.isFinite else {
                throw AgentError.validation("alarm_offsets must contain numbers")
            }
            return offset
        }
    }

    static func optionalStringArray(_ value: JSONValue?, field: String) throws -> [String] {
        guard let value, value != .null else { return [] }
        guard let values = value.arrayValue else {
            throw AgentError.validation("\(field) must be an array")
        }
        return try values.compactMap { element in
            guard let text = element.stringValue else {
                throw AgentError.validation("\(field) must contain strings")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
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
            "attendees": .array(
                items: .string(description: "Attendee email address."),
                description: "Optional attendee email addresses. EventKit writes ignore attendees."
            ),
            "recurrence_rule": .string(description: "Optional RFC 5545 RRULE subset, e.g. FREQ=WEEKLY;BYDAY=MO."),
            "alarm_offsets": .array(
                items: .integer(description: "Alarm offset in seconds relative to start; negative means before."),
                description: "Optional alarm offsets in seconds relative to event start."
            ),
            "calendar_id": .string(
                description: "Target writable calendar id. Omit to use the \"Nexus\" calendar."
            ),
        ]
    }
}
