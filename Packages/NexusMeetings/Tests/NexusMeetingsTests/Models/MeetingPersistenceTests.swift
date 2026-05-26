import Foundation
import NexusSync
import SwiftData
import Testing

@testable import NexusMeetings

// swiftlint:disable:next function_body_length
@Test func meetingAndAudioStorageRoundTripThroughConfiguredModelContainer() throws {
    let container = try NexusModelContainer.makeInMemory(
        extraModels: [Meeting.self],
        localOnlyExtraModels: [MeetingAudioStorage.self]
    )
    let context = ModelContext(container)
    let meetingID = UUID()
    let actionItemID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let updatedAt = Date(timeIntervalSince1970: 1_700_003_600)
    let processedAt = Date(timeIntervalSince1970: 1_700_007_200)
    let speakerSegments = [
        MeetingSpeakerSegment(startMs: 0, endMs: 1500, speaker: "Me", text: "Ship it")
    ]
    let participants = [
        MeetingParticipant(speakerID: "Me", displayName: "Kacper")
    ]
    let segmentsJSON = try MeetingSpeakerSegment.encode(speakerSegments)
    let participantsJSON = try MeetingParticipant.encode(participants)
    let folderURL = URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")

    let meeting = Meeting(
        id: meetingID,
        title: "Design review",
        startedAt: Date(timeIntervalSince1970: 1_699_999_000),
        durationSec: 3_600,
        endedAt: Date(timeIntervalSince1970: 1_700_002_600),
        appBundleID: "com.microsoft.teams2",
        calendarEventID: "calendar-event-1",
        detectionSource: .auto,
        processingStatus: .ready,
        processedAt: processedAt,
        transcriptText: "Full transcript",
        summaryText: "Summary text",
        segmentsJSON: segmentsJSON,
        participantsJSON: participantsJSON,
        actionItemIDs: [actionItemID],
        languageCode: "en",
        providerProfile: "whisperkit-large",
        createdAt: createdAt,
        updatedAt: updatedAt
    )
    let storage = MeetingAudioStorage(
        meetingID: meetingID,
        folderURL: folderURL,
        retentionPolicy: .days7,
        totalBytes: 42,
        hasAudio: true,
        createdAt: createdAt
    )

    context.insert(meeting)
    context.insert(storage)
    try context.save()

    let fetchedMeetings = try context.fetch(FetchDescriptor<Meeting>())
    let fetchedStorages = try context.fetch(FetchDescriptor<MeetingAudioStorage>())
    let fetchedMeeting = try #require(fetchedMeetings.first)
    let fetchedStorage = try #require(fetchedStorages.first)

    #expect(fetchedMeetings.count == 1)
    #expect(fetchedMeeting.id == meetingID)
    #expect(fetchedMeeting.kind == .meeting)
    #expect(fetchedMeeting.title == "Design review")
    #expect(fetchedMeeting.durationSec == 3_600)
    #expect(fetchedMeeting.endedAt == Date(timeIntervalSince1970: 1_700_002_600))
    #expect(fetchedMeeting.appBundleID == "com.microsoft.teams2")
    #expect(fetchedMeeting.calendarEventID == "calendar-event-1")
    #expect(fetchedMeeting.detectionSource == MeetingDetectionSource.auto.rawValue)
    #expect(fetchedMeeting.processingStatus == MeetingProcessingStatus.ready.rawValue)
    #expect(fetchedMeeting.processedAt == processedAt)
    #expect(fetchedMeeting.transcriptText == "Full transcript")
    #expect(fetchedMeeting.summaryText == "Summary text")
    #expect(fetchedMeeting.segmentsJSON == segmentsJSON)
    #expect(fetchedMeeting.participantsJSON == participantsJSON)
    #expect(try MeetingSpeakerSegment.decode(fetchedMeeting.segmentsJSON) == speakerSegments)
    #expect(try MeetingParticipant.decode(try #require(fetchedMeeting.participantsJSON)) == participants)
    #expect(fetchedMeeting.actionItemIDs == [actionItemID])
    #expect(fetchedMeeting.languageCode == "en")
    #expect(fetchedMeeting.providerProfile == "whisperkit-large")
    #expect(fetchedMeeting.createdAt == createdAt)
    #expect(fetchedMeeting.updatedAt == updatedAt)

    #expect(fetchedStorages.count == 1)
    #expect(fetchedStorage.meetingID == meetingID)
    #expect(fetchedStorage.folderURL == folderURL)
    #expect(fetchedStorage.retentionPolicy == MeetingAudioStorage.RetentionPolicy.days7.rawValue)
    #expect(fetchedStorage.totalBytes == 42)
    #expect(fetchedStorage.hasAudio == true)
    #expect(fetchedStorage.createdAt == createdAt)
    #expect(fetchedStorage.expiresAt == createdAt.addingTimeInterval(7 * 86_400))
}
