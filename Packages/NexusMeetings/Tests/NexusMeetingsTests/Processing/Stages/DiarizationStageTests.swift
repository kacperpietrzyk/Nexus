import Foundation
import Testing

@testable import NexusMeetings

@Test func diarizationProducesPerSpeakerSegments() async throws {
    let recorder = DiarizationCallRecorder()
    let audioURL = URL(fileURLWithPath: "/tmp/o.wav")
    let expectedSegments = [
        DiarizationSegment(startMs: 0, endMs: 1_500, speakerID: "Speaker_1"),
        DiarizationSegment(startMs: 1_500, endMs: 3_000, speakerID: "Speaker_2"),
    ]
    let stage = DiarizationStage(sessionLoader: {
        StubDiarizer(segments: expectedSegments, recorder: recorder)
    })
    let segments = try await stage.run(audioURL: audioURL)

    #expect(segments == expectedSegments)
    #expect(await recorder.calls() == [audioURL])
}

@Test func diarizationPropagatesSessionError() async throws {
    let stage = DiarizationStage(sessionLoader: {
        ThrowingDiarizer(error: StubDiarizerError.failed)
    })

    await #expect(throws: StubDiarizerError.failed) {
        try await stage.run(audioURL: URL(fileURLWithPath: "/tmp/o.wav"))
    }
}

private struct StubDiarizer: SortformerSession {
    let segments: [DiarizationSegment]
    let recorder: DiarizationCallRecorder

    func diarize(audioURL: URL) async throws -> [DiarizationSegment] {
        await recorder.record(audioURL)
        return segments
    }
}

private struct ThrowingDiarizer: SortformerSession {
    let error: StubDiarizerError

    func diarize(audioURL: URL) async throws -> [DiarizationSegment] {
        throw error
    }
}

private actor DiarizationCallRecorder {
    private var recordedCalls: [URL] = []

    func record(_ audioURL: URL) {
        recordedCalls.append(audioURL)
    }

    func calls() -> [URL] {
        recordedCalls
    }
}

private enum StubDiarizerError: Error, Equatable {
    case failed
}
