import Foundation
import NexusCore
import NexusSync
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
struct MeetingPeopleLinkerTests {
    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        let container = try NexusModelContainer.makeInMemory(
            extraModels: [Meeting.self, Person.self],
            localOnlyExtraModels: [MeetingAudioStorage.self]
        )
        return ModelContext(container)
    }

    private func meeting(
        participants: [MeetingParticipant] = [],
        calendarEventID: String? = nil
    ) throws -> Meeting {
        let meeting = Meeting(
            title: "Sync",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSec: 1800,
            calendarEventID: calendarEventID,
            detectionSource: .manual,
            participantsJSON: try MeetingParticipant.encode(participants)
        )
        return meeting
    }

    private func activePeople(_ repo: PersonRepository) throws -> [Person] {
        try repo.allActive()
    }

    // MARK: - Speaker pass (primary)

    @Test func mappedDisplayNamesBecomePeopleWithAttendeeEdges() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson"),
            MeetingParticipant(speakerID: "Speaker 2", displayName: "Bob Brown"),
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        #expect(Set(linked.map(\.displayName)) == ["Alice Anderson", "Bob Brown"])
        #expect(try activePeople(repo).count == 2)

        let aggregateAlice = try repo.aggregate(linked.first { $0.displayName == "Alice Anderson" }!)
        #expect(aggregateAlice.meetings == [meeting.id])
    }

    @Test func emptyParticipantsLinkNoPeople() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(participants: [])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        #expect(linked.isEmpty)
        #expect(try activePeople(repo).isEmpty)
    }

    @Test func unmappedSpeakerPlaceholdersAreSkipped() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        // displayName == speakerID means the user never renamed the speaker.
        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Speaker 1"),
            MeetingParticipant(speakerID: "Speaker 2", displayName: "  "),
            MeetingParticipant(speakerID: "Speaker 3", displayName: "Carol"),
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        #expect(linked.map(\.displayName) == ["Carol"])
        #expect(try activePeople(repo).count == 1)
    }

    @Test func rerunIsIdempotentSameSet() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson"),
            MeetingParticipant(speakerID: "Speaker 2", displayName: "Bob Brown"),
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        _ = try await linker.link(meeting: meeting)
        let secondRun = try await linker.link(meeting: meeting)

        #expect(Set(secondRun.map(\.id)).count == 2)
        #expect(try activePeople(repo).count == 2)

        // No duplicate edges either.
        let links = LinkRepository(context: context)
        let edges = try links.backlinks(to: (.person, secondRun[0].id))
        #expect(edges.count == 1)
        #expect(edges.allSatisfy { $0.linkKind == .attendee && $0.fromKind == .meeting })
    }

    @Test func nameReusedAcrossMeetingsStaysOnePerson() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meetingA = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
        ])
        let meetingB = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "alice anderson")
        ])
        context.insert(meetingA)
        context.insert(meetingB)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        _ = try await linker.link(meeting: meetingA)
        let linkedB = try await linker.link(meeting: meetingB)

        // Case-insensitive soft-match keeps a single Person across both meetings.
        #expect(try activePeople(repo).count == 1)
        let alice = linkedB[0]
        let aggregate = try repo.aggregate(alice)
        #expect(Set(aggregate.meetings) == [meetingA.id, meetingB.id])
    }

    @Test func speakerEdgeIsAttendeeNeverMention() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        let links = LinkRepository(context: context)
        let edges = try links.backlinks(to: (.person, linked[0].id))
        // Single-user boundary (I1): meeting → person is ALWAYS .attendee.
        #expect(edges.allSatisfy { $0.linkKind == .attendee })
        #expect(edges.contains { $0.linkKind == .mentions } == false)
    }

    @Test func participantWithPersonIDLinksThatPersonDirectly() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        // A pre-existing contact the user assigned the speaker to.
        let chosen = try repo.create(displayName: "Alice Anderson", email: "alice@example.com")

        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson", personID: chosen.id)
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        // No new Person minted — the chosen one is linked via .attendee.
        #expect(try activePeople(repo).count == 1)
        #expect(linked.map(\.id) == [chosen.id])
        let aggregate = try repo.aggregate(chosen)
        #expect(aggregate.meetings == [meeting.id])
    }

    @Test func personIDChoiceOverridesNumberedPlaceholderSkip() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let chosen = try repo.create(displayName: "Bob")
        // displayName is still a numbered placeholder, but the explicit personID must
        // win — the placeholder filter never drops a user-chosen person.
        let meeting = try meeting(participants: [
            MeetingParticipant(speakerID: "Speaker 1", displayName: "Speaker 1", personID: chosen.id)
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)
        #expect(linked.map(\.id) == [chosen.id])
    }

    @Test func numberedPlaceholderNamesAreNotMinted() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(participants: [
            // All numbered placeholders the user typed/renamed-to but that are not real
            // names — none should mint a Person (root-cause fix for list pollution).
            MeetingParticipant(speakerID: "S1", displayName: "Participant 1"),
            MeetingParticipant(speakerID: "S2", displayName: "participant_2"),
            MeetingParticipant(speakerID: "S3", displayName: "Speaker 3"),
            MeetingParticipant(speakerID: "S4", displayName: "Carol"),
        ])
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo)
        let linked = try await linker.link(meeting: meeting)

        #expect(linked.map(\.displayName) == ["Carol"])
        #expect(try activePeople(repo).map(\.displayName) == ["Carol"])
    }

    @Test func placeholderMatcherRecognizesPatterns() {
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("Participant 1"))
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("participant_2"))
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("Speaker3"))
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("SPEAKER 12"))
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("Anna") == false)
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("Participant Smith") == false)
        #expect(MeetingPeopleLinker.isNumberedPlaceholder("") == false)
    }

    // MARK: - Calendar pass (enrichment)

    @Test func calendarAttendeeEnrichesMatchingSpeakerWithoutDuplicating() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: "evt-1"
        )
        context.insert(meeting)
        try context.save()

        let provider = FakeAttendeeProvider(events: [
            CalendarEvent(
                id: "evt-1",
                title: "Sync",
                start: meeting.startedAt,
                end: meeting.startedAt.addingTimeInterval(1800),
                attendees: [CalendarEvent.Attendee(name: "Alice Anderson", email: "alice@example.com")]
            )
        ])
        let linker = MeetingPeopleLinker(people: repo, calendarProvider: provider)
        let linked = try await linker.link(meeting: meeting)

        // Enrich in place — still one Alice, now with an email.
        #expect(try activePeople(repo).count == 1)
        #expect(linked.count == 1)
        #expect(linked[0].email == "alice@example.com")
    }

    @Test func calendarAttendeeWithoutSpeakerMatchUpsertsByEmail() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: "evt-1"
        )
        context.insert(meeting)
        try context.save()

        let provider = FakeAttendeeProvider(events: [
            CalendarEvent(
                id: "evt-1",
                title: "Sync",
                start: meeting.startedAt,
                end: meeting.startedAt.addingTimeInterval(1800),
                attendees: [CalendarEvent.Attendee(name: "Dave Davis", email: "dave@example.com")]
            )
        ])
        let linker = MeetingPeopleLinker(people: repo, calendarProvider: provider)
        _ = try await linker.link(meeting: meeting)

        // Alice (speaker) + Dave (calendar-only) = two people.
        let active = try activePeople(repo)
        #expect(active.count == 2)
        let dave = active.first { $0.displayName == "Dave Davis" }
        #expect(dave?.email == "dave@example.com")
        #expect(dave?.externalSourceID == "calendar-attendee:dave@example.com")
    }

    @Test func calendarAttendeeWithNameOnlyAndNoMatchIsSkipped() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: "evt-1"
        )
        context.insert(meeting)
        try context.save()

        let provider = FakeAttendeeProvider(events: [
            CalendarEvent(
                id: "evt-1",
                title: "Sync",
                start: meeting.startedAt,
                end: meeting.startedAt.addingTimeInterval(1800),
                // Name-only attendee that matches no existing speaker, no email to key on.
                attendees: [CalendarEvent.Attendee(name: "Unknown Guest", email: nil)]
            )
        ])
        let linker = MeetingPeopleLinker(people: repo, calendarProvider: provider)
        _ = try await linker.link(meeting: meeting)

        // Only the speaker is surfaced; the name-only, unmatched attendee mints nothing.
        let active = try activePeople(repo)
        #expect(active.map(\.displayName) == ["Alice Anderson"])
    }

    @Test func calendarEnrichmentIsIdempotent() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: "evt-1"
        )
        context.insert(meeting)
        try context.save()

        let provider = FakeAttendeeProvider(events: [
            CalendarEvent(
                id: "evt-1",
                title: "Sync",
                start: meeting.startedAt,
                end: meeting.startedAt.addingTimeInterval(1800),
                attendees: [
                    CalendarEvent.Attendee(name: "Alice Anderson", email: "alice@example.com"),
                    CalendarEvent.Attendee(name: "Dave Davis", email: "dave@example.com"),
                ]
            )
        ])
        let linker = MeetingPeopleLinker(people: repo, calendarProvider: provider)
        _ = try await linker.link(meeting: meeting)
        _ = try await linker.link(meeting: meeting)

        #expect(try activePeople(repo).count == 2)
        let links = LinkRepository(context: context)
        for person in try activePeople(repo) {
            let edges = try links.backlinks(to: (.person, person.id))
            #expect(edges.count == 1)
        }
    }

    @Test func calendarProviderErrorDoesNotBreakSpeakerLinking() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: "evt-1"
        )
        context.insert(meeting)
        try context.save()

        let linker = MeetingPeopleLinker(people: repo, calendarProvider: ThrowingAttendeeProvider())
        let linked = try await linker.link(meeting: meeting)

        // Speaker pass still produced Alice despite the failing calendar pass.
        #expect(linked.map(\.displayName) == ["Alice Anderson"])
        #expect(try activePeople(repo).count == 1)
    }

    @Test func noCalendarEventIDSkipsEnrichment() async throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let meeting = try meeting(
            participants: [
                MeetingParticipant(speakerID: "Speaker 1", displayName: "Alice Anderson")
            ],
            calendarEventID: nil
        )
        context.insert(meeting)
        try context.save()

        let provider = FakeAttendeeProvider(events: [
            CalendarEvent(
                id: "evt-1",
                title: "Sync",
                start: meeting.startedAt,
                end: meeting.startedAt.addingTimeInterval(1800),
                attendees: [CalendarEvent.Attendee(name: "Dave Davis", email: "dave@example.com")]
            )
        ])
        let linker = MeetingPeopleLinker(people: repo, calendarProvider: provider)
        _ = try await linker.link(meeting: meeting)

        // calendarEventID == nil → no enrichment, only the speaker.
        #expect(try activePeople(repo).count == 1)
    }
}

// MARK: - Fakes

private struct FakeAttendeeProvider: CalendarEventProviding {
    let events: [CalendarEvent]

    func authorizationStatus() -> CalendarAuthorizationStatus { .fullAccess }
    func requestAccess() async throws -> CalendarAuthorizationStatus { .fullAccess }
    func eventsToday(now: Date) async throws -> [CalendarEvent] { events }
    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        events.filter { $0.end > start && $0.start < end }
    }
}

private struct ThrowingAttendeeProvider: CalendarEventProviding {
    func authorizationStatus() -> CalendarAuthorizationStatus { .fullAccess }
    func requestAccess() async throws -> CalendarAuthorizationStatus { .fullAccess }
    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        throw CalendarProviderError.accessDenied
    }
    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        throw CalendarProviderError.accessDenied
    }
}
