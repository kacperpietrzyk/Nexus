import Foundation
import NexusCore
import NexusSync
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
@Test func transcriptViewModelLoadsSegments() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1000, speaker: "Me", text: "Hi"),
        .init(startMs: 1000, endMs: 2000, speaker: "Speaker_1", text: "Hello"),
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    meeting.participantsJSON = try MeetingParticipant.encode([
        .init(speakerID: "Speaker_1", displayName: "Anna")
    ])
    try repo.insert(meeting)
    let vm = TranscriptViewModel(meetingID: meeting.id, repository: repo)
    vm.load()
    #expect(vm.segments.count == 2)
    #expect(vm.speakerNames.contains("Me"))
    #expect(vm.speakerNames.contains("Speaker_1"))
    #expect(vm.displayName(for: "Me") == "Me")
    #expect(vm.displayName(for: "Speaker_1") == "Anna")
}

@MainActor
@Test func renameSpeakerPersistsParticipants() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "Hello")
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    try repo.insert(meeting)
    let vm = TranscriptViewModel(meetingID: meeting.id, repository: repo)
    vm.load()
    try vm.rename(speaker: "Speaker_1", to: "Anna")
    let reloaded = try repo.find(id: meeting.id)
    let participants = try MeetingParticipant.decode(reloaded?.participantsJSON ?? Data())
    #expect(participants.contains(.init(speakerID: "Speaker_1", displayName: "Anna")))
}

@MainActor
@Test func renameSpeakerPreservesParticipantsAddedAfterLoad() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1000, speaker: "Speaker_1", text: "Hello"),
        .init(startMs: 1000, endMs: 2000, speaker: "Speaker_2", text: "Hi"),
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.updatedAt = Date(timeIntervalSince1970: 100)
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    meeting.participantsJSON = try MeetingParticipant.encode([
        .init(speakerID: "Speaker_1", displayName: "Speaker 1")
    ])
    try repo.insert(meeting)

    let vm = TranscriptViewModel(meetingID: meeting.id, repository: repo)
    vm.load()
    let loadedUpdatedAt = meeting.updatedAt
    meeting.participantsJSON = try MeetingParticipant.encode([
        .init(speakerID: "Speaker_1", displayName: "Speaker 1"),
        .init(speakerID: "Speaker_2", displayName: "Ben"),
    ])
    try repo.upsert(meeting)

    try vm.rename(speaker: "Speaker_1", to: "Anna")

    let reloaded = try #require(try repo.find(id: meeting.id))
    let participants = try MeetingParticipant.decode(reloaded.participantsJSON ?? Data())
    #expect(participants.contains(.init(speakerID: "Speaker_1", displayName: "Anna")))
    #expect(participants.contains(.init(speakerID: "Speaker_2", displayName: "Ben")))
    #expect(reloaded.updatedAt > loadedUpdatedAt)
}

@MainActor
@Test func renameSpeakerTrimsAndIgnoresEmptyDisplayNames() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    meeting.participantsJSON = try MeetingParticipant.encode([
        .init(speakerID: "Speaker_1", displayName: "Original")
    ])
    try repo.insert(meeting)

    let vm = TranscriptViewModel(meetingID: meeting.id, repository: repo)
    vm.load()
    try vm.rename(speaker: "Speaker_1", to: "  Anna\n")
    #expect(vm.displayName(for: "Speaker_1") == "Anna")

    try vm.rename(speaker: "Speaker_1", to: " \n ")
    let reloaded = try #require(try repo.find(id: meeting.id))
    let participants = try MeetingParticipant.decode(reloaded.participantsJSON ?? Data())
    #expect(participants.contains(.init(speakerID: "Speaker_1", displayName: "Anna")))
    #expect(!participants.contains(.init(speakerID: "Speaker_1", displayName: "")))
}

@MainActor
@Test func renameReRendersPersistedTranscriptWithName() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "Hello")
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    meeting.transcriptText = MergeStage().renderLinear(segments)
    try repo.insert(meeting)
    #expect(try #require(try repo.find(id: meeting.id)).transcriptText.contains("Speaker_1"))

    let vm = TranscriptViewModel(meetingID: meeting.id, repository: repo)
    vm.load()
    try vm.rename(speaker: "Speaker_1", to: "Anna")

    let reloaded = try #require(try repo.find(id: meeting.id))
    #expect(reloaded.transcriptText.contains("Anna"))
    #expect(reloaded.transcriptText.contains("Speaker_1") == false)
}

@MainActor
@Test func attendeeSeedDoesNotOverwriteManualChoice() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "Hello")
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    try repo.insert(meeting)

    // The user manually labels Speaker_1 as "Anna".
    let vm = TranscriptViewModel(
        meetingID: meeting.id,
        repository: repo,
        attendeeSeedProvider: { _ in ["Bob Calendar", "Carol Calendar"] }
    )
    vm.load()
    try vm.rename(speaker: "Speaker_1", to: "Anna")

    // Loading attendee suggestions is a pure suggestion surface; it must never
    // mutate the persisted manual mapping (I3).
    await vm.loadAttendeeSuggestions()
    #expect(vm.attendeeSuggestions == ["Bob Calendar", "Carol Calendar"])
    let reloaded = try #require(try repo.find(id: meeting.id))
    let participants = try MeetingParticipant.decode(reloaded.participantsJSON ?? Data())
    #expect(participants == [.init(speakerID: "Speaker_1", displayName: "Anna")])
}

@MainActor
@Test func renameWiresPeopleLinkerCreatingAttendeeIdempotently() async throws {
    let container = try NexusModelContainer.makeInMemory(
        extraModels: [Meeting.self, Person.self],
        localOnlyExtraModels: [MeetingAudioStorage.self]
    )
    let context = ModelContext(container)
    let repo = MeetingRepository(context: context)
    let people = PersonRepository(context: context)
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "Hello")
    ]
    let meeting = MeetingsTestSupport.meeting()
    meeting.segmentsJSON = try MeetingSpeakerSegment.encode(segments)
    try repo.insert(meeting)
    let meetingID = meeting.id

    let linker = MeetingPeopleLinker(people: people)
    let vm = TranscriptViewModel(meetingID: meetingID, repository: repo, peopleLinker: linker)
    vm.load()
    try vm.rename(speaker: "Speaker_1", to: "Anna")

    // The rename fires the linker on a detached MainActor task; drive it directly
    // here too so the assertion is deterministic (the linker is idempotent, so a
    // second invocation must not create a duplicate Person).
    let saved = try #require(try repo.find(id: meetingID))
    _ = try await linker.link(meeting: saved)
    _ = try await linker.link(meeting: saved)

    let active = try people.allActive()
    #expect(active.map(\.displayName) == ["Anna"])
    let aggregate = try people.aggregate(try #require(active.first))
    #expect(aggregate.meetings == [meetingID])
}
