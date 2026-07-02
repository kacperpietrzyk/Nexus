import Foundation
import NexusCore
import SwiftData

/// Surfaces the people on a meeting as `Person` records and wires the
/// `meeting → person` `.attendee` edges, entirely through the `Link` graph in
/// NexusCore (People/Contacts module, spec §2 sources, §4.2, §6).
///
/// **Graph-only — no PeopleFeature import.** This hook depends solely on
/// `PersonRepository` (NexusCore); NexusMeetings never imports the People UI
/// package. Cross-module wiring is done on the polymorphic `Link` graph.
///
/// Two passes, primary-first:
///
/// 1. **Speaker pass (primary).** Each unique non-empty `participantsJSON`
///    `displayName` that the user actually named (i.e. `displayName != speakerID`,
///    so auto-generated "Speaker 1" placeholders are skipped — mirrors
///    `MeetingRepository.distinctParticipantNames`) becomes a `Person` candidate.
///    Existing people are reused via case/diacritic-insensitive name soft-match
///    (`suggestExisting`) so a person named across several meetings stays a single
///    `Person` (invariant I2); only when there is no match is a new row created,
///    keyed `meeting-participant:<displayName>`. A `.attendee` edge is linked.
///
/// 2. **Calendar pass (enrichment, best-effort).** When `Meeting.calendarEventID`
///    is set, EventKit attendees (via the injected `CalendarEventProviding`) ENRICH
///    the people already surfaced: an attendee whose name soft-matches an existing
///    person fills in the email in place (no duplicate row — I2); an unmatched
///    attendee with an email is upserted keyed `calendar-attendee:<email>`. Per the
///    spec caveat, `EKEvent.attendees` is often nil / email-less, so this pass is
///    pure enrichment and swallows provider errors (like `CalendarCorrelator`) — it
///    must never break the primary speaker linking.
///
/// Idempotent: a re-run finds the same people by name soft-match (and
/// `linkAttendee` is `findOrCreate`), so re-processing a meeting yields the same
/// set with no duplicates. Safety here is idempotency, NOT single-save atomicity —
/// a partial failure plus re-run completes without duplicating.
///
/// A `Person` is linked to a meeting ONLY as `.attendee`, never as a task
/// assignee/owner — invariant I1 holds structurally because this hook only ever
/// calls `linkAttendee` (never `linkMention`).
@MainActor
public struct MeetingPeopleLinker {
    private let people: PersonRepository
    private let calendarProvider: (any CalendarEventProviding)?

    /// - Parameters:
    ///   - people: the NexusCore `PersonRepository` (graph-only wiring).
    ///   - calendarProvider: optional EventKit-backed provider used for the
    ///     calendar enrichment pass. Inject a fake in tests; pass `nil` to skip
    ///     enrichment entirely. The linker never requires a granted store — a
    ///     provider that returns no events simply yields no enrichment.
    public init(
        people: PersonRepository,
        calendarProvider: (any CalendarEventProviding)? = nil
    ) {
        self.people = people
        self.calendarProvider = calendarProvider
    }

    /// Surfaces the meeting's people and links `.attendee` edges. The speaker pass
    /// runs first (primary); the calendar pass enriches and never throws on
    /// provider failure. Returns the people linked to this meeting (deduplicated).
    @discardableResult
    public func link(meeting: Meeting) async throws -> [Person] {
        var linked = try linkSpeakers(of: meeting)
        let enriched = await enrichFromCalendar(meeting: meeting)
        for person in enriched where !linked.contains(where: { $0.id == person.id }) {
            linked.append(person)
        }
        return linked
    }

    // MARK: - Speaker pass (primary)

    private func linkSpeakers(of meeting: Meeting) throws -> [Person] {
        let participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
        var linked: [Person] = []
        var seenNames = Set<String>()

        for participant in participants {
            let name = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            // Primary: the user explicitly assigned this speaker to a `Person` in the
            // rename sheet (#3). Link THAT person directly — no name soft-match, no
            // placeholder skip (a chosen person must never be dropped).
            if let personID = participant.personID, let person = try people.find(id: personID) {
                let key = "id:\(personID.uuidString)"
                guard seenNames.insert(key).inserted else { continue }
                try people.linkAttendee(meetingID: meeting.id, personID: person.id)
                linked.append(person)
                continue
            }

            // Skip empties, auto-generated placeholders the user never renamed
            // (`displayName == speakerID`), and numbered "Participant N" / "Speaker N"
            // labels — those are not real names and minting `Person` rows for them is
            // the source of the People-list pollution this fix removes (#4b).
            guard
                !name.isEmpty,
                name != participant.speakerID,
                !Self.isNumberedPlaceholder(name)
            else { continue }
            // Dedupe within a single meeting case/diacritic-insensitively.
            let key = Self.fold(name)
            guard seenNames.insert(key).inserted else { continue }

            let person: Person
            if let existing = try people.suggestExisting(matching: name) {
                person = existing
            } else {
                person = try people.create(
                    displayName: name,
                    externalSourceID: "meeting-participant:\(name)"
                )
            }
            try people.linkAttendee(meetingID: meeting.id, personID: person.id)
            linked.append(person)
        }
        return linked
    }

    // MARK: - Calendar pass (enrichment, best-effort)

    private func enrichFromCalendar(meeting: Meeting) async -> [Person] {
        guard
            let eventID = meeting.calendarEventID,
            let provider = calendarProvider
        else {
            return []
        }

        let attendees = await attendees(forEventID: eventID, of: meeting, provider: provider)
        guard !attendees.isEmpty else { return [] }

        var enriched: [Person] = []
        for attendee in attendees {
            let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = attendee.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonEmptyName = (name?.isEmpty == false) ? name : nil
            let nonEmptyEmail = (email?.isEmpty == false) ? email : nil

            let person: Person?
            if let nonEmptyName, let existing = try? people.suggestExisting(matching: nonEmptyName) {
                // Enrich the already-surfaced person in place — no duplicate row (I2).
                // Only FILL a missing email; never overwrite a curated one.
                // suggestExisting is a fuzzy displayName/alias match, so a different
                // person who merely shares a name or alias would otherwise have their
                // real email clobbered by this attendee (re-applied on every reprocess).
                let existingEmailIsBlank =
                    existing.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                if let nonEmptyEmail, existingEmailIsBlank {
                    try? people.update(existing, email: .some(nonEmptyEmail))
                }
                person = existing
            } else if let nonEmptyEmail {
                // No speaker match: upsert keyed on the email (idempotent re-import).
                person = try? people.upsert(
                    externalSourceID: "calendar-attendee:\(nonEmptyEmail)",
                    displayName: nonEmptyName ?? nonEmptyEmail,
                    email: nonEmptyEmail
                )
            } else {
                // Name-only attendee with no existing speaker match: pure enrichment,
                // nothing to key on. Skip rather than mint a bare contact record from
                // calendar data the spec calls "often nil/no-email" (avoids junk/near-
                // duplicate rows). A name-only attendee only matters when it matches an
                // already-surfaced person (handled above).
                person = nil
            }

            guard let person else { continue }
            _ = try? people.linkAttendee(meetingID: meeting.id, personID: person.id)
            enriched.append(person)
        }
        return enriched
    }

    /// Resolves the meeting's calendar event to its attendees. `CalendarEventProviding`
    /// has no fetch-by-id, so we query a padded window around the meeting and match
    /// by event id (the same window idiom `CalendarCorrelator` uses). Best-effort:
    /// any provider error yields no attendees so the primary pass is never broken.
    private func attendees(
        forEventID eventID: String,
        of meeting: Meeting,
        provider: any CalendarEventProviding
    ) async -> [CalendarEvent.Attendee] {
        let pad: TimeInterval = 15 * 60
        let end = meeting.endedAt ?? meeting.startedAt.addingTimeInterval(TimeInterval(meeting.durationSec))
        let lower = meeting.startedAt.addingTimeInterval(-pad)
        let upper = max(end, meeting.startedAt).addingTimeInterval(pad)
        do {
            let events = try await provider.eventsBetween(start: lower, end: upper)
            return events.first { $0.id == eventID }?.attendees ?? []
        } catch {
            return []
        }
    }

    /// Matches auto-generated placeholder labels like "Participant 1", "Speaker_2",
    /// "speaker 3" (case-insensitive, optional space/underscore before the digits).
    /// These are never real names, so the linker must not mint `Person` rows for them
    /// — that minting was the root cause of the People-list "Participant N" pollution.
    static func isNumberedPlaceholder(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: "^(participant|speaker)[ _]?\\d+$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Case/diacritic-insensitive fold for intra-meeting name de-duplication
    /// (mirrors `PersonRepository`'s name soft-match folding). Used only to avoid
    /// linking the same person twice from one participants list; cross-meeting
    /// dedup is `PersonRepository.suggestExisting`.
    private static func fold(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .init(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
