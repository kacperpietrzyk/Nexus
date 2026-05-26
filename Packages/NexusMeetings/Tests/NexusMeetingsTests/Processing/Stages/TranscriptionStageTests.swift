import Foundation
import Testing

@testable import NexusMeetings

@Test func transcriptionStageProcessesBothTracksInParallel() async throws {
    let primaryRecorder = TranscriptionCallRecorder()
    let fallbackRecorder = TranscriptionCallRecorder()
    let primary = StubProvider(
        id: "stub-primary",
        result: .init(
            text: "Cześć",
            segments: [.init(startMs: 0, endMs: 500, text: "Cześć")],
            detectedLanguage: "pl"
        ),
        recorder: primaryRecorder
    )
    let fallback = StubProvider(
        id: "stub-fallback",
        result: .init(
            text: "Słyszę was",
            segments: [.init(startMs: 500, endMs: 1_500, text: "Słyszę was")],
            detectedLanguage: "pl"
        ),
        recorder: fallbackRecorder
    )
    let meURL = URL(fileURLWithPath: "/tmp/me.wav")
    let othersURL = URL(fileURLWithPath: "/tmp/others.wav")
    let stage = TranscriptionStage(primary: primary, fallback: fallback)

    let output = try await stage.run(
        meURL: meURL,
        othersURL: othersURL,
        languageHint: "pl"
    )

    #expect(output.me.text == "Cześć")
    #expect(output.others.text == "Cześć")
    #expect(output.providerProfile == "stub-primary")
    #expect(output.detectedLanguage == "pl")
    #expect(
        Set(await primaryRecorder.calls())
            == Set([
                .init(audioURL: meURL, languageHint: "pl"),
                .init(audioURL: othersURL, languageHint: "pl"),
            ]))
    #expect(await fallbackRecorder.calls().isEmpty)
}

@Test func transcriptionStageFallsBackOnEmptyPrimary() async throws {
    let primaryRecorder = TranscriptionCallRecorder()
    let fallbackRecorder = TranscriptionCallRecorder()
    let empty = StubProvider(
        id: "empty",
        result: .init(text: "", segments: [], detectedLanguage: "und"),
        recorder: primaryRecorder
    )
    let fallback = StubProvider(
        id: "fb",
        result: .init(
            text: "Result",
            segments: [.init(startMs: 0, endMs: 100, text: "Result")],
            detectedLanguage: "pl"
        ),
        recorder: fallbackRecorder
    )
    let meURL = URL(fileURLWithPath: "/tmp/me.wav")
    let othersURL = URL(fileURLWithPath: "/tmp/others.wav")
    let stage = TranscriptionStage(primary: empty, fallback: fallback)

    let output = try await stage.run(
        meURL: meURL,
        othersURL: othersURL,
        languageHint: nil
    )

    #expect(output.me.text == "Result")
    #expect(output.others.text == "Result")
    #expect(output.providerProfile.contains("fb"))
    #expect(output.detectedLanguage == "pl")
    #expect(
        Set(await primaryRecorder.calls())
            == Set([
                .init(audioURL: meURL, languageHint: nil),
                .init(audioURL: othersURL, languageHint: nil),
            ]))
    #expect(
        Set(await fallbackRecorder.calls())
            == Set([
                .init(audioURL: meURL, languageHint: nil),
                .init(audioURL: othersURL, languageHint: nil),
            ]))
}

@Test func transcriptionStageFallsBackOnWhitespaceOnlyPrimary() async throws {
    let whitespace = StubProvider(
        id: "whitespace",
        result: .init(text: " \n\t ", segments: [], detectedLanguage: "und"),
        recorder: TranscriptionCallRecorder()
    )
    let fallback = StubProvider(
        id: "fb",
        result: .init(
            text: "Fallback",
            segments: [.init(startMs: 0, endMs: 500, text: "Fallback")],
            detectedLanguage: "en"
        ),
        recorder: TranscriptionCallRecorder()
    )
    let stage = TranscriptionStage(primary: whitespace, fallback: fallback)

    let output = try await stage.run(
        meURL: URL(fileURLWithPath: "/tmp/me.wav"),
        othersURL: URL(fileURLWithPath: "/tmp/others.wav"),
        languageHint: nil
    )

    #expect(output.me.text == "Fallback")
    #expect(output.others.text == "Fallback")
    #expect(output.providerProfile == "fb")
    #expect(output.detectedLanguage == "en")
}

@Test func transcriptionStageUsesOthersDetectedLanguageWhenMeIsEmptyUndetected() async throws {
    let meURL = URL(fileURLWithPath: "/tmp/me.wav")
    let othersURL = URL(fileURLWithPath: "/tmp/others.wav")
    let primary = URLRoutingProvider(
        id: "primary",
        results: [
            meURL: .init(text: "", segments: [], detectedLanguage: "und"),
            othersURL: .init(
                text: "Słyszę was",
                segments: [.init(startMs: 0, endMs: 1_000, text: "Słyszę was")],
                detectedLanguage: "pl"
            ),
        ]
    )
    let fallback = StubProvider(
        id: "fallback",
        result: .init(text: "Fallback", segments: [], detectedLanguage: "en"),
        recorder: TranscriptionCallRecorder()
    )
    let stage = TranscriptionStage(primary: primary, fallback: fallback)

    let output = try await stage.run(
        meURL: meURL,
        othersURL: othersURL,
        languageHint: nil
    )

    #expect(output.providerProfile == "primary")
    #expect(output.detectedLanguage == "pl")
}

@Test func transcriptionStagePrefersLanguageHintOverEmptyTrackDetectedLanguage() async throws {
    let meURL = URL(fileURLWithPath: "/tmp/me.wav")
    let othersURL = URL(fileURLWithPath: "/tmp/others.wav")
    let primary = URLRoutingProvider(
        id: "primary",
        results: [
            meURL: .init(
                text: "Text without language",
                segments: [.init(startMs: 0, endMs: 1_000, text: "Text without language")],
                detectedLanguage: "und"
            ),
            othersURL: .init(text: " \n\t ", segments: [], detectedLanguage: "pl"),
        ]
    )
    let fallback = StubProvider(
        id: "fallback",
        result: .init(text: "Fallback", segments: [], detectedLanguage: "pl"),
        recorder: TranscriptionCallRecorder()
    )
    let stage = TranscriptionStage(primary: primary, fallback: fallback)

    let output = try await stage.run(
        meURL: meURL,
        othersURL: othersURL,
        languageHint: "en-US"
    )

    #expect(output.providerProfile == "primary")
    #expect(output.detectedLanguage == "en")
}

@Test func transcriptionStageDoesNotFallbackWhenOnlyOnePrimaryTrackIsUnderThreshold() async throws {
    let fallbackRecorder = TranscriptionCallRecorder()
    let meURL = URL(fileURLWithPath: "/tmp/me.wav")
    let othersURL = URL(fileURLWithPath: "/tmp/others.wav")
    let primary = URLRoutingProvider(
        id: "primary",
        results: [
            meURL: .init(text: "", segments: [], detectedLanguage: "und"),
            othersURL: .init(
                text: "Enough",
                segments: [.init(startMs: 0, endMs: 500, text: "Enough")],
                detectedLanguage: "en"
            ),
        ]
    )
    let fallback = StubProvider(
        id: "fallback",
        result: .init(text: "Fallback", segments: [], detectedLanguage: "pl"),
        recorder: fallbackRecorder
    )
    let stage = TranscriptionStage(primary: primary, fallback: fallback)

    let output = try await stage.run(
        meURL: meURL,
        othersURL: othersURL,
        languageHint: nil
    )

    #expect(output.me.text.isEmpty)
    #expect(output.others.text == "Enough")
    #expect(output.providerProfile == "primary")
    #expect(await fallbackRecorder.calls().isEmpty)
}

@Test func transcriptionStageStartsBothPrimaryTracksBeforeEitherReturns() async throws {
    let barrier = TranscriptionStartBarrier(expectedTrackCount: 2)
    let primary = BarrierProvider(
        id: "barrier-primary",
        barrier: barrier,
        result: .init(
            text: "Ready",
            segments: [.init(startMs: 0, endMs: 100, text: "Ready")],
            detectedLanguage: "en"
        )
    )
    let fallback = StubProvider(
        id: "fallback",
        result: .init(text: "Fallback", segments: [], detectedLanguage: "en"),
        recorder: TranscriptionCallRecorder()
    )
    let stage = TranscriptionStage(primary: primary, fallback: fallback)

    let output = try await stage.run(
        meURL: URL(fileURLWithPath: "/tmp/me.wav"),
        othersURL: URL(fileURLWithPath: "/tmp/others.wav"),
        languageHint: "en"
    )

    #expect(output.me.text == "Ready")
    #expect(output.others.text == "Ready")
    #expect(await barrier.startedTrackCount() == 2)
}

private struct TranscriptionCall: Equatable, Hashable, Sendable {
    let audioURL: URL
    let languageHint: String?
}

private actor TranscriptionCallRecorder {
    private var recordedCalls: [TranscriptionCall] = []

    func record(audioURL: URL, languageHint: String?) {
        recordedCalls.append(.init(audioURL: audioURL, languageHint: languageHint))
    }

    func calls() -> [TranscriptionCall] {
        recordedCalls
    }
}

private struct StubProvider: MeetingTranscriptionProvider {
    let id: String
    let result: TranscriptionResult
    let recorder: TranscriptionCallRecorder

    var identifier: String { id }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        await recorder.record(audioURL: audioURL, languageHint: languageHint)
        return result
    }
}

private struct URLRoutingProvider: MeetingTranscriptionProvider {
    let id: String
    let results: [URL: TranscriptionResult]

    var identifier: String { id }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        results[audioURL] ?? .init(text: "", segments: [], detectedLanguage: "und")
    }
}

private struct BarrierProvider: MeetingTranscriptionProvider {
    let id: String
    let barrier: TranscriptionStartBarrier
    let result: TranscriptionResult

    var identifier: String { id }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await barrier.waitUntilExpectedTracksStarted(audioURL: audioURL)
        return result
    }
}

private actor TranscriptionStartBarrier {
    private let expectedTrackCount: Int
    private var startedTracks: Set<URL> = []

    init(expectedTrackCount: Int) {
        self.expectedTrackCount = expectedTrackCount
    }

    func waitUntilExpectedTracksStarted(audioURL: URL) async throws {
        startedTracks.insert(audioURL)

        let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
        while startedTracks.count < expectedTrackCount {
            guard ContinuousClock.now < deadline else {
                throw TranscriptionBarrierError.timedOut(startedTracks.count)
            }

            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func startedTrackCount() -> Int {
        startedTracks.count
    }
}

private enum TranscriptionBarrierError: Error, Equatable {
    case timedOut(Int)
}
