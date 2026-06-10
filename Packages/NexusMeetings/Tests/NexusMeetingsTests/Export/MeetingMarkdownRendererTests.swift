import Foundation
import NexusCore
import Testing

@testable import NexusMeetings

private let sampleSummary = """
    ## TL;DR
    Shipped the exporter.

    ## Decisions made
    - Use markdown

    ## Key topics
    - Export pipeline
    """

@Test func body_rendersSummaryActionItemsAndTranscriptInOrder() {
    let taskID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let doneID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let body = MeetingMarkdownRenderer.body(
        summary: MeetingSummarySections.parse(summaryText: sampleSummary),
        actionItems: [
            MeetingMarkdownRenderer.ActionItem(id: taskID, title: "Send notes", isDone: false),
            MeetingMarkdownRenderer.ActionItem(id: doneID, title: "Book room", isDone: true),
        ],
        segments: [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_500, speaker: "Me", text: "Hello"),
            MeetingSpeakerSegment(startMs: 65_000, endMs: 70_000, speaker: "Speaker_1", text: "Hi there"),
        ],
        participants: [MeetingParticipant(speakerID: "Speaker_1", displayName: "Alice")],
        transcriptText: "ignored when segments exist"
    )
    let expected = """
        ## Summary

        Shipped the exporter.

        ### Decisions

        - Use markdown

        ### Key topics

        - Export pipeline

        ## Action items

        - [ ] Send notes (task:22222222-2222-2222-2222-222222222222)
        - [x] Book room (task:33333333-3333-3333-3333-333333333333)

        ## Transcript

        - [00:00:00] Me: Hello
        - [00:01:05] Alice: Hi there
        """
    #expect(body == expected)
}

@Test func body_omitsEmptySections() {
    let body = MeetingMarkdownRenderer.body(
        summary: .empty,
        actionItems: [],
        segments: [],
        participants: [],
        transcriptText: ""
    )
    #expect(body.isEmpty)
}

@Test func body_fallsBackToRawTranscriptWhenNoSegments() {
    let body = MeetingMarkdownRenderer.body(
        summary: .empty,
        actionItems: [],
        segments: [],
        participants: [],
        transcriptText: "Raw linear transcript\n"
    )
    #expect(body == "## Transcript\n\nRaw linear transcript")
}

@Test func transcript_timestampsRollPastOneHour() {
    let body = MeetingMarkdownRenderer.body(
        summary: .empty,
        actionItems: [],
        segments: [
            MeetingSpeakerSegment(startMs: 3_725_000, endMs: 3_730_000, speaker: "Me", text: "Late")
        ],
        participants: [],
        transcriptText: ""
    )
    #expect(body == "## Transcript\n\n- [01:02:05] Me: Late")
}

@Test func frontmatterExtras_emitsDeterministicFields() {
    let startedAt = Date(timeIntervalSince1970: 1_699_999_000)
    let extras = MeetingMarkdownRenderer.frontmatterExtras(
        startedAt: startedAt,
        durationSec: 1_800,
        participants: [
            MeetingParticipant(speakerID: "Speaker_1", displayName: "Alice"),
            MeetingParticipant(speakerID: "Speaker_2", displayName: "   "),
        ],
        calendarEventID: "cal-1"
    )
    #expect(extras.count == 4)
    #expect(extras[0].0 == "startedAt")
    #expect(extras[0].1 == .date(startedAt))
    #expect(extras[1].0 == "durationSec")
    #expect(extras[1].1 == .string("1800"))
    #expect(extras[2].0 == "attendees")
    #expect(extras[2].1 == .list([.string("Alice")]))
    #expect(extras[3].0 == "calendarEventID")
    #expect(extras[3].1 == .string("cal-1"))
}

@Test func frontmatterExtras_encodesNilCalendarEventAsNull() {
    let extras = MeetingMarkdownRenderer.frontmatterExtras(
        startedAt: Date(timeIntervalSince1970: 0),
        durationSec: 0,
        participants: [],
        calendarEventID: nil
    )
    #expect(extras[3].0 == "calendarEventID")
    #expect(extras[3].1 == FrontmatterValue.none)
}
