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
    /// The event organizer, when EventKit exposes one. Distinct from `attendees`
    /// so the editor / meeting surfaces can label who convened the event (#4a).
    public let organizer: Attendee?
    /// The free-text notes / description body carried by the invite. Previously
    /// URL-scanned then discarded; now retained so the editor and meeting
    /// surfaces can show it (#4a).
    public let notes: String?
    /// Extracted Microsoft Teams meeting identifier (digits only), when the
    /// invite carries one (#4a). Parsed from the notes / join URL.
    public let meetingID: String?

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
        calendarID: String? = nil,
        organizer: Attendee? = nil,
        notes: String? = nil,
        meetingID: String? = nil
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
        self.organizer = organizer
        self.notes = notes
        self.meetingID = meetingID
    }

    public struct Attendee: Hashable, Sendable {
        public let name: String?
        public let email: String?
        /// Per-attendee invitation response, when EventKit exposes it (#4a).
        public let responseStatus: ResponseStatus?
        /// The attendee's role in the meeting, when EventKit exposes it (#4a).
        public let role: Role?
        /// Whether this participant is the current user / device owner (#4a).
        public let isCurrentUser: Bool

        public init(
            name: String? = nil,
            email: String? = nil,
            responseStatus: ResponseStatus? = nil,
            role: Role? = nil,
            isCurrentUser: Bool = false
        ) {
            self.name = name
            self.email = email
            self.responseStatus = responseStatus
            self.role = role
            self.isCurrentUser = isCurrentUser
        }
    }

    /// Nexus-domain mirror of `EKParticipantStatus` (kept EventKit-free so the
    /// core domain stays pure; the provider maps from EventKit).
    public enum ResponseStatus: String, Hashable, Sendable {
        case accepted
        case declined
        case tentative
        case pending
    }

    /// Nexus-domain mirror of `EKParticipantRole` (the meaningful subset).
    public enum Role: String, Hashable, Sendable {
        case required
        case optional
        case chair
    }
}
