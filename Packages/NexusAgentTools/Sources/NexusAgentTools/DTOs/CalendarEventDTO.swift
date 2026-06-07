import Foundation
import NexusCore

/// Wire format for a calendar event read back from the store (spec §9 / §12
/// `calendar.events.list`). Mirrors `CalendarEventSnapshot` plus the read-side
/// fields the `CalendarEventProviding` view exposes (location, attendees).
public struct CalendarEventDTO: Codable, Sendable, Equatable {
    public let id: String
    public let calendarID: String?
    public let title: String
    public let start: String
    public let end: String
    public let isAllDay: Bool
    public let location: String?
    public let attendees: [String]

    private enum CodingKeys: String, CodingKey {
        case id, title, start, end, location, attendees
        case calendarID = "calendar_id"
        case isAllDay = "is_all_day"
    }

    public init(
        id: String,
        calendarID: String?,
        title: String,
        start: String,
        end: String,
        isAllDay: Bool,
        location: String?,
        attendees: [String]
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.attendees = attendees
    }

    public init(from event: CalendarEvent) {
        self.id = event.id
        self.calendarID = nil
        self.title = event.title
        self.start = ScheduleDTOFormatter.string(event.start)
        self.end = ScheduleDTOFormatter.string(event.end)
        self.isAllDay = false
        self.location = event.location
        self.attendees = event.attendees.compactMap { $0.email ?? $0.name }
    }

    public init(from snapshot: CalendarEventSnapshot) {
        self.id = snapshot.eventID
        self.calendarID = snapshot.calendarID
        self.title = snapshot.title
        self.start = ScheduleDTOFormatter.string(snapshot.start)
        self.end = ScheduleDTOFormatter.string(snapshot.end)
        self.isAllDay = false
        self.location = nil
        self.attendees = []
    }
}
