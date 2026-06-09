import Foundation
import NexusCore

/// A ranked calendar-attendee suggestion offered in the speaker rename sheet (#4b).
///
/// Built from the now-richer `CalendarEvent.Attendee` data (name + email +
/// `responseStatus` + `role` + `isCurrentUser`). Unlike the old name-only `String`
/// seed, a candidate carries enough to (a) rank sensibly and (b) pre-fill a `Person`
/// match by email when the user picks it — never auto-assigned (I3, suggestion only).
public struct MeetingAttendeeCandidate: Identifiable, Hashable, Sendable {
    public var id: String { email?.lowercased() ?? name.lowercased() }
    public let name: String
    public let email: String?
    public let responseStatus: CalendarEvent.ResponseStatus?
    public let role: CalendarEvent.Role?

    public init(
        name: String,
        email: String? = nil,
        responseStatus: CalendarEvent.ResponseStatus? = nil,
        role: CalendarEvent.Role? = nil
    ) {
        self.name = name
        self.email = email
        self.responseStatus = responseStatus
        self.role = role
    }

    /// A subtle one-word hint shown under the name (declined / tentative / organizer),
    /// or `nil` when the attendee is a plain accepted/pending required participant
    /// (no hint avoids visual noise on the common case).
    public var statusHint: String? {
        if role == .chair { return "Organizer" }
        switch responseStatus {
        case .declined: return "Declined"
        case .tentative: return "Tentative"
        case .accepted, .pending, .none: return nil
        }
    }
}
