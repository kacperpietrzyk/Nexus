import Foundation
import NexusCore
import Testing

@testable import NexusMeetings

@Suite struct AttendeeCandidateRankingTests {
    /// The current user ("Me") is never offered as a speaker candidate.
    @Test func currentUserIsExcluded() {
        let ranked = MeetingsComposition.rankAttendeeCandidates([
            CalendarEvent.Attendee(name: "Me", email: "me@example.com", isCurrentUser: true),
            CalendarEvent.Attendee(name: "Anna", email: "anna@example.com"),
        ])
        #expect(ranked.map(\.name) == ["Anna"])
    }

    /// Declined invitees sink below accepted ones; tentative sits between.
    @Test func declinedRanksBelowTentativeBelowAccepted() {
        let ranked = MeetingsComposition.rankAttendeeCandidates([
            CalendarEvent.Attendee(name: "Declined", email: "d@example.com", responseStatus: .declined),
            CalendarEvent.Attendee(name: "Accepted", email: "a@example.com", responseStatus: .accepted),
            CalendarEvent.Attendee(name: "Tentative", email: "t@example.com", responseStatus: .tentative),
        ])
        #expect(ranked.map(\.name) == ["Accepted", "Tentative", "Declined"])
    }

    /// Email-keyed de-duplication keeps the first occurrence; nameless, emailless
    /// attendees are dropped (nothing readable to offer).
    @Test func dedupesByEmailAndDropsEmpty() {
        let ranked = MeetingsComposition.rankAttendeeCandidates([
            CalendarEvent.Attendee(name: "Anna", email: "anna@example.com"),
            CalendarEvent.Attendee(name: "Anna (dup)", email: "ANNA@example.com"),
            CalendarEvent.Attendee(name: nil, email: nil),
            CalendarEvent.Attendee(name: "  ", email: nil),
        ])
        #expect(ranked.map(\.name) == ["Anna"])
    }

    /// An email-only attendee is still pickable (falls back to email as the label).
    @Test func emailOnlyAttendeeFallsBackToEmailLabel() {
        let ranked = MeetingsComposition.rankAttendeeCandidates([
            CalendarEvent.Attendee(name: nil, email: "ghost@example.com")
        ])
        #expect(ranked.map(\.name) == ["ghost@example.com"])
    }

    /// The status hint surfaces organizer / declined / tentative, and stays nil for
    /// the plain accepted case to avoid visual noise.
    @Test func statusHintReflectsRoleAndResponse() {
        #expect(
            MeetingAttendeeCandidate(name: "Chair", role: .chair).statusHint == "Organizer"
        )
        #expect(
            MeetingAttendeeCandidate(name: "D", responseStatus: .declined).statusHint == "Declined"
        )
        #expect(
            MeetingAttendeeCandidate(name: "T", responseStatus: .tentative).statusHint == "Tentative"
        )
        #expect(
            MeetingAttendeeCandidate(name: "A", responseStatus: .accepted).statusHint == nil
        )
    }
}
