import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusMeetings

/// Fully-populated fixture for the standalone-document golden: fixed id,
/// fixed epochs, diarized segments + a named participant, one action item.
private func makeStandupMeeting(actionItemID: UUID) throws -> Meeting {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    return Meeting(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        title: "Standup",
        startedAt: Date(timeIntervalSince1970: 1_699_999_000),
        durationSec: 1_800,
        calendarEventID: "cal-1",
        detectionSource: .manual,
        processingStatus: .ready,
        transcriptText: "Hello Hi there",
        summaryText: "## TL;DR\nShipped the exporter.",
        segmentsJSON: try MeetingSpeakerSegment.encode([
            MeetingSpeakerSegment(startMs: 0, endMs: 1_500, speaker: "Me", text: "Hello"),
            MeetingSpeakerSegment(startMs: 65_000, endMs: 70_000, speaker: "Speaker_1", text: "Hi there"),
        ]),
        participantsJSON: try MeetingParticipant.encode([
            MeetingParticipant(speakerID: "Speaker_1", displayName: "Alice")
        ]),
        actionItemIDs: [actionItemID],
        createdAt: when,
        updatedAt: when
    )
}

@MainActor
@Test func exportMarkdownDocument_rendersFullStandaloneDocument() throws {
    let context = try MeetingsTestSupport.makeContext()
    let task = TaskItem(title: "Send notes")
    context.insert(task)

    let meeting = try makeStandupMeeting(actionItemID: task.id)
    context.insert(meeting)
    try context.save()

    let document = meeting.exportMarkdownDocument(in: context)
    let expected = """
        ---
        id: 11111111-1111-1111-1111-111111111111
        kind: meeting
        title: Standup
        createdAt: 2023-11-14T22:13:20Z
        updatedAt: 2023-11-14T22:13:20Z
        deletedAt: null
        startedAt: 2023-11-14T21:56:40Z
        durationSec: 1800
        attendees:
          - Alice
        calendarEventID: cal-1
        links: []
        ---

        # Standup

        ## Summary

        Shipped the exporter.

        ## Action items

        - [ ] Send notes (task:\(task.id.uuidString))

        ## Transcript

        - [00:00:00] Me: Hello
        - [00:01:05] Alice: Hi there

        """
    #expect(document == expected)
}

@MainActor
@Test func markdownExporter_globalExport_writesMeetingFile() async throws {
    let container = try MeetingsTestSupport.makeContainer()
    let context = ModelContext(container)

    let task = TaskItem(title: "Send notes")
    context.insert(task)
    let meeting = MeetingsTestSupport.meeting(
        title: "Weekly sync",
        status: .ready,
        transcript: "Raw transcript",
        summary: "## TL;DR\nShort recap."
    )
    meeting.actionItemIDs = [task.id]
    context.insert(meeting)
    context.insert(
        Link(from: (.meeting, meeting.id), to: (.task, task.id), linkKind: .actionItem))
    try context.save()

    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-meeting-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(
        container: container, types: Meeting.self, to: folder)
    #expect(result.itemsExported == 1)
    #expect(result.linksAttached == 1)

    let text = try String(
        contentsOf: folder.appendingPathComponent("\(meeting.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(text.contains("kind: meeting"))
    #expect(text.contains("startedAt: 2023-11-14T22:13:20Z"))
    #expect(text.contains("durationSec: 1800"))
    #expect(text.contains("## Summary"))
    #expect(text.contains("Short recap."))
    #expect(text.contains("- [ ] Send notes (task:\(task.id.uuidString))"))
    #expect(text.contains("## Transcript"))
    #expect(text.contains("Raw transcript"))
    #expect(text.contains("linkKind: actionItem"))
}
