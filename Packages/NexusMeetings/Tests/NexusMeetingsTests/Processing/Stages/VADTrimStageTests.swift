import Foundation
import Testing

@testable import NexusMeetings

@Test func vadTrimComputesTimingOffsets() async throws {
    let stage = VADTrimStage(sileroLoader: { StubSilero(speechRanges: [(500, 4_500)]) })
    let output = try await stage.run(
        audioURL: URL(fileURLWithPath: "/tmp/x.wav"),
        durationMs: 5_000
    )

    #expect(output.speechRanges.first?.startMs == 500)
    #expect(output.speechRanges.first?.endMs == 4_500)
    #expect(output.headTrimMs == 500)
    #expect(output.tailTrimMs == 500)
}

@Test func vadTrimMergesNestedOverlappingRangesBeforeComputingTailTrim() async throws {
    let output = try await output(
        speechRanges: [(1_000, 9_000), (8_000, 8_500)],
        durationMs: 10_000
    )

    #expect(output.speechRanges == [VADSpeechRange(startMs: 1_000, endMs: 9_000)])
    #expect(output.headTrimMs == 1_000)
    #expect(output.tailTrimMs == 1_000)
}

@Test func vadTrimSortsUnsortedRanges() async throws {
    let output = try await output(
        speechRanges: [(4_000, 5_000), (1_000, 2_000)],
        durationMs: 10_000
    )

    #expect(
        output.speechRanges == [
            VADSpeechRange(startMs: 1_000, endMs: 2_000),
            VADSpeechRange(startMs: 4_000, endMs: 5_000),
        ])
    #expect(output.headTrimMs == 1_000)
    #expect(output.tailTrimMs == 5_000)
}

@Test func vadTrimClampsOutOfBoundsRanges() async throws {
    let output = try await output(
        speechRanges: [(-100, 500), (800, 2_000)],
        durationMs: 1_000
    )

    #expect(
        output.speechRanges == [
            VADSpeechRange(startMs: 0, endMs: 500),
            VADSpeechRange(startMs: 800, endMs: 1_000),
        ])
    #expect(output.headTrimMs == 0)
    #expect(output.tailTrimMs == 0)
}

@Test func vadTrimDropsReversedRanges() async throws {
    let output = try await output(
        speechRanges: [(900, 700), (100, 200)],
        durationMs: 1_000
    )

    #expect(output.speechRanges == [VADSpeechRange(startMs: 100, endMs: 200)])
    #expect(output.headTrimMs == 100)
    #expect(output.tailTrimMs == 800)
}

@Test func vadTrimHandlesEmptyRanges() async throws {
    let output = try await output(speechRanges: [], durationMs: 5_000)

    #expect(output.speechRanges.isEmpty)
    #expect(output.headTrimMs == 0)
    #expect(output.tailTrimMs == 0)
}

@Test func vadTrimHandlesNegativeDuration() async throws {
    let output = try await output(
        speechRanges: [(100, 200)],
        durationMs: -1
    )

    #expect(output.speechRanges.isEmpty)
    #expect(output.headTrimMs == 0)
    #expect(output.tailTrimMs == 0)
}

@Test func vadMillisecondsConversionRejectsNonFiniteAndOutOfRangeValues() {
    #expect(FluidAudioSileroSession.milliseconds(from: .nan) == nil)
    #expect(FluidAudioSileroSession.milliseconds(from: .infinity) == nil)
    #expect(FluidAudioSileroSession.milliseconds(from: -.infinity) == nil)
    #expect(FluidAudioSileroSession.milliseconds(from: Double(Int.max) / 1_000 + 1) == nil)
    #expect(FluidAudioSileroSession.milliseconds(from: 1.25) == 1_250)
}

@Test func vadTotalSamplesClampsOverflowAndNegativeDurations() {
    #expect(FluidAudioSileroSession.totalSamples(durationMs: -1) == 0)
    #expect(FluidAudioSileroSession.totalSamples(durationMs: 1_000) == 16_000)
    #expect(FluidAudioSileroSession.totalSamples(durationMs: Int.max) == Int.max)
}

private func output(speechRanges: [(Int, Int)], durationMs: Int) async throws -> VADTrimOutput {
    let stage = VADTrimStage(sileroLoader: { StubSilero(speechRanges: speechRanges) })
    return try await stage.run(
        audioURL: URL(fileURLWithPath: "/tmp/x.wav"),
        durationMs: durationMs
    )
}

private struct StubSilero: SileroVADSession {
    let speechRanges: [(Int, Int)]

    func detectSpeechRanges(audioURL: URL, durationMs: Int) async throws -> [VADSpeechRange] {
        speechRanges.map { VADSpeechRange(startMs: $0.0, endMs: $0.1) }
    }
}
