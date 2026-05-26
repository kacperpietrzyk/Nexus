import Foundation
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
@Test func insertAndFetchByID() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(title: "First")
    try repo.insert(meeting)
    let fetched = try repo.find(id: meeting.id)
    #expect(fetched?.title == "First")
}

@MainActor
@Test func upsertReplacesExisting() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let original = MeetingsTestSupport.meeting(title: "v1")
    try repo.insert(original)
    let actionID = UUID()
    let endedAt = Date(timeIntervalSince1970: 1_710_003_600)
    let segmentsJSON = Data(#"[{"speaker":"A","text":"hello"}]"#.utf8)
    let participantsJSON = Data(#"[{"name":"Alicja"}]"#.utf8)
    let modified = Meeting(
        title: "v2",
        startedAt: Date(timeIntervalSince1970: 1_710_000_000),
        durationSec: 3600,
        endedAt: endedAt,
        appBundleID: "us.zoom.xos",
        calendarEventID: "calendar-1",
        detectionSource: .imported,
        processingStatus: .ready,
        processedAt: Date(timeIntervalSince1970: 1_710_004_000),
        transcriptText: "transcript",
        summaryText: "summary",
        segmentsJSON: segmentsJSON,
        participantsJSON: participantsJSON,
        actionItemIDs: [actionID],
        languageCode: "pl",
        providerProfile: "whisper-large",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
    modified.id = original.id
    try repo.upsert(modified)
    let fetched = try repo.find(id: original.id)
    #expect(fetched?.title == "v2")
    #expect(fetched?.endedAt == endedAt)
    #expect(fetched?.calendarEventID == "calendar-1")
    #expect(fetched?.detectionSource == MeetingDetectionSource.imported.rawValue)
    #expect(fetched?.processingStatus == MeetingProcessingStatus.ready.rawValue)
    #expect(fetched?.segmentsJSON == segmentsJSON)
    #expect(fetched?.participantsJSON == participantsJSON)
    #expect(fetched?.actionItemIDs == [actionID])
    #expect(fetched?.languageCode == "pl")
    #expect(fetched?.providerProfile == "whisper-large")
    let count = try repo.allChronological().count
    #expect(count == 1)
}

@MainActor
@Test func upsertCopiesIncomingDeletedAt() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let original = MeetingsTestSupport.meeting(title: "active")
    try repo.insert(original)
    let deletedAt = Date(timeIntervalSince1970: 1_720_000_000)
    let modified = MeetingsTestSupport.meeting(title: "deleted")
    modified.id = original.id
    modified.deletedAt = deletedAt

    try repo.upsert(modified)

    let fetched = try repo.find(id: original.id)
    #expect(fetched?.deletedAt == deletedAt)
}

@MainActor
@Test func upsertClearsExistingDeletedAt() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let original = MeetingsTestSupport.meeting(title: "deleted")
    original.deletedAt = Date(timeIntervalSince1970: 1_720_000_000)
    try repo.insert(original)
    let restored = MeetingsTestSupport.meeting(title: "restored")
    restored.id = original.id
    restored.deletedAt = nil

    try repo.upsert(restored)

    let fetched = try repo.find(id: original.id)
    #expect(fetched?.deletedAt == nil)
}

@MainActor
@Test func allChronologicalOrdersByStartedAtDesc() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let older = MeetingsTestSupport.meeting(
        title: "older",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let newer = MeetingsTestSupport.meeting(
        title: "newer",
        startedAt: Date(timeIntervalSince1970: 1_710_000_000)
    )
    try repo.insert(older)
    try repo.insert(newer)
    let all = try repo.allChronological()
    #expect(all.first?.title == "newer")
    #expect(all.last?.title == "older")
}

@MainActor
@Test func deleteCascadesIntoAudioStorage() throws {
    let context = try MeetingsTestSupport.makeContext()
    let meetingRepo = MeetingRepository(context: context)
    let storageRepo = MeetingAudioStorageRepository(context: context)
    let meeting = MeetingsTestSupport.meeting()
    try meetingRepo.insert(meeting)
    let storage = MeetingAudioStorage(
        meetingID: meeting.id,
        folderURL: URL(fileURLWithPath: "/tmp/\(meeting.id)"),
        retentionPolicy: .days30
    )
    try storageRepo.insert(storage)
    try meetingRepo.delete(id: meeting.id)
    #expect(try meetingRepo.find(id: meeting.id) == nil)
    #expect(try storageRepo.find(meetingID: meeting.id) == nil)
}
