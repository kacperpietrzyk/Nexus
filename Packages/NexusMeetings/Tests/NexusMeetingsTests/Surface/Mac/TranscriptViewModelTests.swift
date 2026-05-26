import Foundation
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
