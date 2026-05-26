import Foundation
import Testing

@testable import NexusMeetings

// MARK: - Fixture helpers

private func writeMinimalBundleManifestAndMeeting(to folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: folder.appendingPathComponent("meetings"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: folder.appendingPathComponent("transcripts"), withIntermediateDirectories: true)
    let manifest = #"""
        {
          "schemaVersion": 1, "source": "circleback-mcp",
          "exportedAt": "2026-05-15T12:00:00Z",
          "counts": {"meetings": 1, "transcripts": 1, "actionItems": 1},
          "meetings": [{"id": 8771435, "linkId": "ttun24m4ILcBPMr2ts4rK",
                        "title": "Weekly sync", "createdAt": "2026-05-14T10:00:13.554Z"}]
        }
        """#
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    // Synthetic meeting JSON uses "title" (plan convention); real Circleback ReadMeetings uses "name".
    let meetingJSON = #"""
        {
          "id": 8771435, "linkId": "ttun24m4ILcBPMr2ts4rK",
          "title": "Weekly sync", "createdAt": "2026-05-14T10:00:13.554Z",
          "duration": 1800.0, "notes": "#### Summary\nShort.",
          "attendees": [{"name": "Participant 1", "email": null}],
          "actionItems": [{"id": 14206966, "title": "Send the deck",
                           "description": "Email by Friday.",
                           "assignee": {"name": "Participant 1", "email": null},
                           "status": "PENDING"}],
          "insights": {}, "tags": [], "url": null, "icalUid": null
        }
        """#
    try Data(meetingJSON.utf8).write(to: folder.appendingPathComponent("meetings/8771435.json"))
}

private func writeMinimalBundleTranscriptAndActions(to folder: URL) throws {
    let transcriptJSON = #"""
        {"meetingId": "ttun24m4ILcBPMr2ts4rK", "meetingName": "Weekly sync",
         "transcript": [{"speaker": "Participant 1", "text": "Hello", "timestamp": 12.43},
                        {"speaker": "Participant 2", "text": "Hi", "timestamp": 18.48}]}
        """#
    try Data(transcriptJSON.utf8).write(
        to: folder.appendingPathComponent("transcripts/ttun24m4ILcBPMr2ts4rK.json"))
    let actionItemsJSON = #"""
        {"schemaVersion": 1, "exportedAt": "2026-05-15T12:00:00Z",
         "items": [{"id": 14206966, "title": "Send the deck",
                    "description": "Email by Friday.",
                    "status": "PENDING", "completedAt": null,
                    "createdAt": "2026-05-14T10:30:00.000Z",
                    "assignee": {"profileId": 14587519, "name": "Participant 1",
                                 "email": "p1@example.com"},
                    "meeting": {"id": 8771435, "name": "Weekly sync",
                                "createdAt": "2026-05-14T10:00:13.554Z"}}]}
        """#
    try Data(actionItemsJSON.utf8).write(to: folder.appendingPathComponent("action-items.json"))
}

// MARK: - Tests

@Test func nexusExportParsesMinimalBundle() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("nex-\(UUID().uuidString)")
    try writeMinimalBundleManifestAndMeeting(to: folder)
    try writeMinimalBundleTranscriptAndActions(to: folder)

    let plan = try NexusExportFormat().plan(bundleURL: folder)
    #expect(plan.meetings.count == 1)
    let meeting = plan.meetings.first!
    #expect(meeting.externalID == 8_771_435)
    #expect(meeting.externalLinkID == "ttun24m4ILcBPMr2ts4rK")
    #expect(meeting.title == "Weekly sync")
    #expect(meeting.durationSec == 1800)
    let createdAt = ISO8601DateFormatter.withFractionalSeconds
        .date(from: "2026-05-14T10:00:13.554Z")!
    // startedAt = createdAt − 1800s
    #expect(abs(meeting.startedAt.timeIntervalSince(createdAt.addingTimeInterval(-1800))) < 0.01)
    #expect(meeting.transcriptSegments.count == 2)
    #expect(meeting.transcriptSegments.first?.text == "Hello")
    #expect(meeting.transcriptText.contains("Hello"))
    #expect(meeting.attendees.first?.name == "Participant 1")
    #expect(meeting.externalSourceID == "circleback:meeting:8771435")
    // endedAt falls out as startedAt + durationSec == createdAt
    #expect(abs(meeting.endedAt.timeIntervalSince(createdAt)) < 0.01)
    #expect(meeting.actionItems.count == 1)
    let action = meeting.actionItems.first!
    #expect(action.externalID == 14_206_966)
    #expect(action.externalSourceID == "circleback:actionItem:14206966")
    #expect(action.status == .pending)
    #expect(action.circlebackCreatedAt != nil)  // present because it came from global action-items.json
}

@Test func nexusExportSkipsMeetingMissingFromFilesystem() throws {
    // Manifest references a meeting whose meetings/<id>.json is absent — must surface as skipped.
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("nex-skip-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: folder.appendingPathComponent("meetings"), withIntermediateDirectories: true)
    let manifest = #"""
        {"schemaVersion": 1, "source": "circleback-mcp",
         "exportedAt": "2026-05-15T12:00:00Z",
         "counts": {"meetings": 1, "transcripts": 0, "actionItems": 0},
         "meetings": [{"id": 999, "linkId": "abc", "title": "Ghost",
                       "createdAt": "2026-05-14T10:00:13.554Z"}]}
        """#
    try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))

    let plan = try NexusExportFormat().plan(bundleURL: folder)
    #expect(plan.meetings.isEmpty)
    #expect(plan.skipped.contains { $0.reason.contains("Missing meeting record") })
}

@Test func nexusExportParsesRealSanitizedFixture() throws {
    let folder = Bundle.module.url(
        forResource: "nexus-export",
        withExtension: nil,
        subdirectory: "Fixtures"
    )!
    let plan = try NexusExportFormat().plan(bundleURL: folder)

    #expect(plan.meetings.count == 2)
    for meeting in plan.meetings {
        #expect(!meeting.transcriptSegments.isEmpty)
        #expect(meeting.externalSourceID.hasPrefix("circleback:meeting:"))
        #expect(!meeting.actionItems.isEmpty)
    }
}
