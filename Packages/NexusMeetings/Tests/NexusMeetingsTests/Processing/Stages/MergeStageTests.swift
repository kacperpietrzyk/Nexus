import Foundation
import Testing

@testable import NexusMeetings

@Test func mergeAlignsMeAndOthersByTimestamp() {
    let me = TranscriptionResult(
        text: "Cześć",
        segments: [.init(startMs: 0, endMs: 1_000, text: "Cześć")],
        detectedLanguage: "pl"
    )
    let others = TranscriptionResult(
        text: "Słyszę was",
        segments: [.init(startMs: 2_000, endMs: 3_000, text: "Słyszę was")],
        detectedLanguage: "pl"
    )
    let diar = [DiarizationSegment(startMs: 2_000, endMs: 3_000, speakerID: "Speaker_1")]
    let stage = MergeStage()

    let segs = stage.merge(me: me, others: others, othersDiarization: diar)

    #expect(segs[0].speaker == "Me")
    #expect(segs[0].text == "Cześć")
    #expect(segs[1].speaker == "Speaker_1")
    #expect(segs[1].text == "Słyszę was")
}

@Test func mergeRenderLinearProducesTimestampedBlocks() {
    let stage = MergeStage()
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Me", text: "Hi"),
        .init(startMs: 1_000, endMs: 2_000, speaker: "Speaker_1", text: "Hello"),
    ]

    let text = stage.renderLinear(segments)

    #expect(text.contains("[00:00:00] Me"))
    #expect(text.contains("[00:00:01] Speaker_1"))
    #expect(text.contains("Hi"))
    #expect(text.contains("Hello"))
}

@Test func mergeRenderLinearSubstitutesMappedSpeakerNames() {
    let stage = MergeStage()
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Me", text: "Hi"),
        .init(startMs: 1_000, endMs: 2_000, speaker: "Speaker_1", text: "Hello"),
        .init(startMs: 2_000, endMs: 3_000, speaker: "Speaker_2", text: "Hey"),
    ]
    let participants = [
        MeetingParticipant(speakerID: "Speaker_1", displayName: "Anna"),
        // Placeholder left at its speakerID -> not substituted.
        MeetingParticipant(speakerID: "Speaker_2", displayName: "Speaker_2"),
    ]

    let text = stage.renderLinear(segments, participants: participants)

    #expect(text.contains("[00:00:01] Anna"))
    // Unmapped "Me" and placeholder "Speaker_2" keep their raw tokens.
    #expect(text.contains("[00:00:00] Me"))
    #expect(text.contains("[00:00:02] Speaker_2"))
    #expect(text.contains("Speaker_1") == false)
}

@Test func mergeRenderLinearWithoutParticipantsMatchesLegacyRender() {
    let stage = MergeStage()
    let segments: [MeetingSpeakerSegment] = [
        .init(startMs: 0, endMs: 1_000, speaker: "Me", text: "Hi"),
        .init(startMs: 1_000, endMs: 2_000, speaker: "Speaker_1", text: "Hello"),
    ]
    #expect(stage.renderLinear(segments, participants: []) == stage.renderLinear(segments))
}

@Test func mergeFallsBackToLargestDiarizationOverlap() {
    let me = TranscriptionResult(text: "", segments: [], detectedLanguage: "en")
    let others = TranscriptionResult(
        text: "Mostly second speaker",
        segments: [.init(startMs: 1_000, endMs: 3_000, text: "Mostly second speaker")],
        detectedLanguage: "en"
    )
    let diarization = [
        DiarizationSegment(startMs: 0, endMs: 1_500, speakerID: "Speaker_1"),
        DiarizationSegment(startMs: 1_500, endMs: 3_500, speakerID: "Speaker_2"),
    ]
    let stage = MergeStage()

    let segs = stage.merge(me: me, others: others, othersDiarization: diarization)

    #expect(
        segs == [
            MeetingSpeakerSegment(
                startMs: 1_000,
                endMs: 3_000,
                speaker: "Speaker_2",
                text: "Mostly second speaker"
            )
        ])
}

@Test func mergeBreaksContainmentTiesDeterministicallyByEarliestStart() {
    // Two diarization turns both fully contain the segment. The speaker must be
    // chosen deterministically (earliest-starting container), never by array order.
    let me = TranscriptionResult(text: "", segments: [], detectedLanguage: "en")
    let others = TranscriptionResult(
        text: "Ambiguous",
        segments: [.init(startMs: 1_000, endMs: 2_000, text: "Ambiguous")],
        detectedLanguage: "en"
    )
    // Better (earlier-starting) container listed SECOND, so array-order would mispick.
    let diarization = [
        DiarizationSegment(startMs: 500, endMs: 2_500, speakerID: "Speaker_B"),
        DiarizationSegment(startMs: 0, endMs: 3_000, speakerID: "Speaker_A"),
    ]
    let stage = MergeStage()

    let segs = stage.merge(me: me, others: others, othersDiarization: diarization)

    #expect(segs.first?.speaker == "Speaker_A")
}

@Test func mergeDefaultsOthersToSpeakerOneWithoutDiarization() {
    let me = TranscriptionResult(text: "", segments: [], detectedLanguage: "en")
    let others = TranscriptionResult(
        text: "No diarization",
        segments: [.init(startMs: 0, endMs: 1_000, text: "No diarization")],
        detectedLanguage: "en"
    )
    let stage = MergeStage()

    let segs = stage.merge(me: me, others: others, othersDiarization: [])

    #expect(
        segs == [
            MeetingSpeakerSegment(startMs: 0, endMs: 1_000, speaker: "Speaker_1", text: "No diarization")
        ])
}

@Test func mergeDefaultsOthersToSpeakerOneWhenDiarizationHasNoOverlap() {
    let me = TranscriptionResult(text: "", segments: [], detectedLanguage: "en")
    let others = TranscriptionResult(
        text: "No temporal overlap",
        segments: [.init(startMs: 4_000, endMs: 5_000, text: "No temporal overlap")],
        detectedLanguage: "en"
    )
    let diarization = [
        DiarizationSegment(startMs: 0, endMs: 1_000, speakerID: "Speaker_9")
    ]
    let stage = MergeStage()

    let segs = stage.merge(me: me, others: others, othersDiarization: diarization)

    #expect(
        segs == [
            MeetingSpeakerSegment(startMs: 4_000, endMs: 5_000, speaker: "Speaker_1", text: "No temporal overlap")
        ])
}
