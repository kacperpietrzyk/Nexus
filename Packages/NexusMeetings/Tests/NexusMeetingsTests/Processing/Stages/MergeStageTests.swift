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
