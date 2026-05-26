import Foundation
import SwiftData
import Testing

@testable import NexusMeetings

@Test func meetingDefaultsAreSane() throws {
    let meeting = Meeting(
        title: "Weekly sync",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSec: 1800,
        appBundleID: "com.microsoft.teams2",
        detectionSource: .auto
    )
    #expect(meeting.title == "Weekly sync")
    #expect(meeting.durationSec == 1800)
    #expect(meeting.processingStatus == MeetingProcessingStatus.recording.rawValue)
    #expect(meeting.detectionSource == MeetingDetectionSource.auto.rawValue)
    #expect(meeting.segmentsJSON.isEmpty == false)
    #expect(meeting.actionItemIDs.isEmpty)
    #expect(meeting.languageCode == nil)
    #expect(meeting.processedAt == nil)
}

@Test func meetingLinkableKindMatchesSchema() {
    let meeting = Meeting(title: "Weekly", startedAt: Date(timeIntervalSince1970: 0), detectionSource: .manual)
    #expect(meeting.kind == .meeting)
}

@Test func meetingPreservesDistinctCreatedAndUpdatedTimestamps() {
    let createdAt = Date(timeIntervalSince1970: 0)
    let updatedAt = Date(timeIntervalSince1970: 31_536_000)
    let meeting = Meeting(
        title: "Imported weekly",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        detectionSource: .imported,
        createdAt: createdAt,
        updatedAt: updatedAt
    )

    #expect(meeting.createdAt == createdAt)
    #expect(meeting.updatedAt == updatedAt)
}
