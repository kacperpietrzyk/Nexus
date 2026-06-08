import Foundation
import SwiftData
import Testing

@testable import NexusMeetings

/// Speaker-aware transcript search (spec §6). Covers the pure segment-filter
/// helper, the repository `speaker:` path, and the invariant that `speaker == nil`
/// is byte-for-byte today's behaviour.
@MainActor
struct MeetingSpeakerSearchTests {
    // MARK: - Pure helper (MergeStage.segments(_:forSpeaker:participants:))

    @Test func helperFiltersByRawDiarizedToken() {
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "budget"),
            MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "timeline"),
            MeetingSpeakerSegment(startMs: 2_000, endMs: 3_000, speaker: "Me", text: "agenda"),
        ]
        let only1 = MergeStage.segments(segments, forSpeaker: "Speaker_1", participants: [])
        #expect(only1.map(\.text) == ["budget"])

        let onlyMe = MergeStage.segments(segments, forSpeaker: "Me", participants: [])
        #expect(onlyMe.map(\.text) == ["agenda"])
    }

    @Test func helperFiltersByLabeledDisplayName() {
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "budget"),
            MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "timeline"),
        ]
        let participants = [
            MeetingParticipant(speakerID: "Speaker_1", displayName: "Alíce"),
            MeetingParticipant(speakerID: "Speaker_2", displayName: "Bob"),
        ]
        // Case- and diacritic-insensitive: "alice" finds "Alíce".
        let alice = MergeStage.segments(segments, forSpeaker: "alice", participants: participants)
        #expect(alice.map(\.text) == ["budget"])
    }

    @Test func helperMatchesRawTokenEvenWhenLabeled() {
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "budget")
        ]
        let participants = [MeetingParticipant(speakerID: "Speaker_1", displayName: "Alice")]
        // The raw token still resolves once a display name exists.
        let byToken = MergeStage.segments(segments, forSpeaker: "Speaker_1", participants: participants)
        #expect(byToken.map(\.text) == ["budget"])
    }

    @Test func helperReturnsEmptyForUnknownSpeaker() {
        let segments = [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "budget")
        ]
        #expect(MergeStage.segments(segments, forSpeaker: "Nobody", participants: []).isEmpty)
    }

    // MARK: - Repository speaker filter

    @Test func speakerFilterReturnsOnlyMeetingsWhereThatSpeakerSaidQuery() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)

        // Speaker_1 says "budget" here.
        try repo.insert(
            makeMeeting(
                title: "Has match",
                startedAt: 1_700_000_000,
                segments: [
                    MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "the budget is fixed"),
                    MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "timeline slips"),
                ]
            ))
        // "budget" is said, but by Speaker_2 — must NOT match a Speaker_1 filter.
        try repo.insert(
            makeMeeting(
                title: "Wrong speaker",
                startedAt: 1_700_003_600,
                segments: [
                    MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "hello there"),
                    MeetingSpeakerSegment(startMs: 1_000, endMs: 2_000, speaker: "Speaker_2", text: "the budget is fixed"),
                ]
            ))

        let hits = try repo.search(query: "budget", limit: 10, speaker: "Speaker_1")
        #expect(hits.map(\.title) == ["Has match"])
    }

    @Test func speakerFilterResolvesDisplayName() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        try repo.insert(
            makeMeeting(
                title: "Labeled",
                startedAt: 1_700_000_000,
                segments: [
                    MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "ship the release")
                ],
                participants: [MeetingParticipant(speakerID: "Speaker_1", displayName: "Alice")]
            ))

        #expect(try repo.search(query: "ship", limit: 10, speaker: "Alice").map(\.title) == ["Labeled"])
        #expect(try repo.search(query: "ship", limit: 10, speaker: "Bob").isEmpty)
    }

    @Test func nilSpeakerKeepsTodaysSearchableTextBehaviour() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        // No segments at all — only title/transcript/summary. Speaker mode would
        // find nothing here; nil mode must still match via searchableText.
        try repo.insert(MeetingsTestSupport.meeting(title: "Weekly", transcript: "Discuss Project Aurora launch."))
        try repo.insert(MeetingsTestSupport.meeting(title: "Other", transcript: "Budget review."))

        let hits = try repo.search(query: "aurora", limit: 10)
        #expect(hits.map(\.title) == ["Weekly"])

        // Explicit nil is identical to the default.
        #expect(try repo.search(query: "aurora", limit: 10, speaker: nil).map(\.title) == ["Weekly"])
    }

    @Test func speakerFilterIgnoresTitleAndSummaryCorpus() throws {
        let context = try MeetingsTestSupport.makeContext()
        let repo = MeetingRepository(context: context)
        // "budget" appears in title/summary but no segment says it → speaker mode
        // must not match (corpus is per-speaker segment text, not searchableText).
        let meeting = makeMeeting(
            title: "Budget sync",
            startedAt: 1_700_000_000,
            segments: [
                MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "hello")
            ]
        )
        meeting.summaryText = "We covered the budget."
        try repo.insert(meeting)

        #expect(try repo.search(query: "budget", limit: 10, speaker: "Speaker_1").isEmpty)
        // But nil mode finds it through the title/summary.
        #expect(try repo.search(query: "budget", limit: 10).map(\.title) == ["Budget sync"])
    }

    // MARK: - Helpers

    private func makeMeeting(
        title: String,
        startedAt: TimeInterval,
        segments: [MeetingSpeakerSegment],
        participants: [MeetingParticipant] = []
    ) -> Meeting {
        Meeting(
            title: title,
            startedAt: Date(timeIntervalSince1970: startedAt),
            detectionSource: .manual,
            transcriptText: segments.map(\.text).joined(separator: "\n"),
            segmentsJSON: (try? MeetingSpeakerSegment.encode(segments)) ?? Data("[]".utf8),
            participantsJSON: participants.isEmpty ? nil : try? MeetingParticipant.encode(participants)
        )
    }
}
