import Foundation

public struct CalendarEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let attendees: [Attendee]
    public let isVideoCall: Bool
    public let urlForJoin: URL?
    public let calendarColorHex: String?
    public let isAllDay: Bool
    /// The owning calendar's stable identifier, when known. Lets a reader
    /// distinguish which calendar an event lives on (agent `calendar.events.list`).
    public let calendarID: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        attendees: [Attendee] = [],
        isVideoCall: Bool = false,
        urlForJoin: URL? = nil,
        calendarColorHex: String? = nil,
        isAllDay: Bool = false,
        calendarID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.attendees = attendees
        self.isVideoCall = isVideoCall
        self.urlForJoin = urlForJoin
        self.calendarColorHex = calendarColorHex
        self.isAllDay = isAllDay
        self.calendarID = calendarID
    }

    public struct Attendee: Hashable, Sendable {
        public let name: String?
        public let email: String?

        public init(name: String? = nil, email: String? = nil) {
            self.name = name
            self.email = email
        }
    }
}
