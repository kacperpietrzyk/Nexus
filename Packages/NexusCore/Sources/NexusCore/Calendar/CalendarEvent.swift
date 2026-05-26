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

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        attendees: [Attendee] = [],
        isVideoCall: Bool = false,
        urlForJoin: URL? = nil,
        calendarColorHex: String? = nil
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
