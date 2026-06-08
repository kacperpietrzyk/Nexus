import Foundation
import Testing
@preconcurrency import WhisperKit

@testable import NexusMeetings

private actor RecordingTranscriber: WhisperKitMeetingTranscribing {
    private(set) var lastPromptTokens: [Int]?
    private let tokens: [Int]?

    init(tokens: [Int]?) {
        self.tokens = tokens
    }

    func transcribe(
        audioPath: String,
        decodeOptions: DecodingOptions
    ) async throws -> [WhisperKitMeetingRawResult] {
        lastPromptTokens = decodeOptions.promptTokens
        return [WhisperKitMeetingRawResult(text: "ok", segments: [], language: "en")]
    }

    nonisolated func promptTokens(for text: String) -> [Int]? { tokens }

    func recordedPromptTokens() -> [Int]? { lastPromptTokens }
}

struct WhisperKitMeetingProviderVocabularyTests {
    /// Creates a temp folder shaped like a usable local WhisperKit model (the
    /// three required `.mlmodelc` directories) so the engine's folder gate passes
    /// and the injected fake loader actually runs. Caller removes it.
    private func makeFakeModelFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-model-\(UUID().uuidString)", isDirectory: true)
        for model in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent("\(model).mlmodelc", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return folder
    }

    @Test func vocabularyPromptJoinsCanonicalSpellings() {
        let prompt = WhisperKitMeetingProviderMapping.vocabularyPrompt([
            CustomVocabularyEntry(term: "threat forge", replacement: "ThreatForge"),
            CustomVocabularyEntry(term: "kube", replacement: "Kube"),
        ])
        #expect(prompt == "ThreatForge, Kube")
    }

    @Test func vocabularyPromptFallsBackToTermWhenNoReplacement() {
        let prompt = WhisperKitMeetingProviderMapping.vocabularyPrompt([
            CustomVocabularyEntry(term: "ACME", replacement: "")
        ])
        #expect(prompt == "ACME")
    }

    @Test func emptyVocabularyHasNilPrompt() {
        #expect(WhisperKitMeetingProviderMapping.vocabularyPrompt([]) == nil)
        #expect(
            WhisperKitMeetingProviderMapping.vocabularyPrompt([
                CustomVocabularyEntry(term: "  ", replacement: "  ")
            ]) == nil
        )
    }

    @Test func nonEmptyVocabularyThreadsPromptTokensIntoDecoding() async throws {
        let folder = try makeFakeModelFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transcriber = RecordingTranscriber(tokens: [11, 22, 33])
        let provider = WhisperKitMeetingProvider(
            localModelFolder: folder,
            vocabularyProvider: { [CustomVocabularyEntry(term: "x", replacement: "X")] },
            loader: { _ in transcriber }
        )
        _ = try await provider.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav"), languageHint: "en") { _ in }
        #expect(await transcriber.recordedPromptTokens() == [11, 22, 33])
    }

    @Test func emptyVocabularyLeavesPromptTokensNil() async throws {
        let folder = try makeFakeModelFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let transcriber = RecordingTranscriber(tokens: [11, 22, 33])
        let provider = WhisperKitMeetingProvider(
            localModelFolder: folder,
            vocabularyProvider: { [] },
            loader: { _ in transcriber }
        )
        _ = try await provider.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav"), languageHint: "en") { _ in }
        #expect(await transcriber.recordedPromptTokens() == nil)
    }
}
