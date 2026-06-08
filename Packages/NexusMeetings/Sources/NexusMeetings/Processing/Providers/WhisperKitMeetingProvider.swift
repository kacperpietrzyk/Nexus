import Foundation
import NexusAI
@preconcurrency import WhisperKit

public enum MeetingTranscriptionProviderError: Error, Equatable, Sendable {
    case localModelUnavailable(String?)
}

public final class WhisperKitMeetingProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    public let identifier = "whisperkit-large"

    private let engine: WhisperKitMeetingProviderEngine

    /// - Parameter vocabularyProvider: returns the user's custom vocabulary, used
    ///   to *bias* transcription via WhisperKit's prompt tokens (best-effort —
    ///   requires the loaded tokenizer; an empty list leaves decoding unchanged).
    ///   The deterministic post-merge replacement (see `CustomVocabularyReplacer`)
    ///   is what actually enforces canonical spelling; this only nudges the ASR.
    public init(
        vocabularyProvider: @escaping @Sendable () -> [CustomVocabularyEntry] = {
            UserDefaultsCustomVocabularyStore.shared.load()
        }
    ) {
        self.engine = WhisperKitMeetingProviderEngine(
            resolveModelFolder: { WhisperKitProvider.defaultLocalModelFolder() },
            tokenizerFolder: WhisperKitProvider.defaultDownloadBase(),
            vocabularyProvider: vocabularyProvider
        )
    }

    init(
        localModelFolder: URL?,
        vocabularyProvider: @escaping @Sendable () -> [CustomVocabularyEntry] = { [] },
        loader: @escaping WhisperKitMeetingProviderEngine.Loader
    ) {
        self.engine = WhisperKitMeetingProviderEngine(
            resolveModelFolder: { localModelFolder },
            vocabularyProvider: vocabularyProvider,
            loader: loader
        )
    }

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await engine.transcribe(audioURL: audioURL, languageHint: languageHint, progress: progress)
    }

    /// Shares NexusAI's persisted WhisperKit model location, so a model
    /// downloaded once (via ``WhisperKitModelDownloadCoordinator``) is visible to
    /// both the meetings engine and the Settings availability badge.
    public static func defaultLocalModelFolder() -> URL? {
        WhisperKitProvider.defaultLocalModelFolder()
    }
}

protocol WhisperKitMeetingTranscribing: Sendable {
    func transcribe(audioPath: String, decodeOptions: DecodingOptions) async throws -> [WhisperKitMeetingRawResult]
    /// Encodes a prompt string to decoder token IDs using the loaded tokenizer,
    /// or `nil` when no tokenizer is available. Used to bias decoding toward
    /// custom-vocabulary spellings (best-effort).
    func promptTokens(for text: String) -> [Int]?
}

extension WhisperKitMeetingTranscribing {
    func promptTokens(for text: String) -> [Int]? { nil }
}

struct WhisperKitMeetingRawResult: Sendable {
    let text: String
    let segments: [WhisperKitMeetingRawSegment]
    let language: String
}

struct WhisperKitMeetingRawSegment: Sendable {
    let start: Float
    let end: Float
    let text: String
    let words: [WhisperKitMeetingRawWord]
}

struct WhisperKitMeetingRawWord: Sendable {
    let start: Float
    let end: Float
    let text: String
}

final class LiveWhisperKitMeetingTranscriber: WhisperKitMeetingTranscribing, @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(modelFolder: URL, tokenizerFolder: URL?) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        self.whisperKit = try await WhisperKit(config)
    }

    func promptTokens(for text: String) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, let tokenizer = whisperKit.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + trimmed).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    func transcribe(audioPath: String, decodeOptions: DecodingOptions) async throws -> [WhisperKitMeetingRawResult] {
        let results = try await whisperKit.transcribe(audioPath: audioPath, decodeOptions: decodeOptions)
        return results.map { result in
            WhisperKitMeetingRawResult(
                text: result.text,
                segments: result.segments.map { segment in
                    WhisperKitMeetingRawSegment(
                        start: segment.start,
                        end: segment.end,
                        text: segment.text,
                        words: segment.words?.map { word in
                            WhisperKitMeetingRawWord(
                                start: word.start,
                                end: word.end,
                                text: word.word
                            )
                        } ?? []
                    )
                },
                language: result.language
            )
        }
    }
}

actor WhisperKitMeetingProviderEngine {
    typealias Loader = @Sendable (URL) async throws -> any WhisperKitMeetingTranscribing

    private let resolveModelFolder: @Sendable () -> URL?
    private let vocabularyProvider: @Sendable () -> [CustomVocabularyEntry]
    private let loader: Loader
    private var transcriber: (any WhisperKitMeetingTranscribing)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        resolveModelFolder: @escaping @Sendable () -> URL?,
        tokenizerFolder: URL? = nil,
        vocabularyProvider: @escaping @Sendable () -> [CustomVocabularyEntry] = { [] },
        loader: Loader? = nil
    ) {
        self.resolveModelFolder = resolveModelFolder
        self.vocabularyProvider = vocabularyProvider
        self.loader =
            loader
            ?? { folder in
                try await LiveWhisperKitMeetingTranscriber(
                    modelFolder: folder, tokenizerFolder: tokenizerFolder)
            }
    }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        await enter()
        defer { leave() }

        await progress(0.05)
        let transcriber = try await loadIfNeeded()
        await progress(0.25)

        let normalizedLanguageHint = WhisperKitMeetingProviderMapping.normalizedDecodingLanguage(
            from: languageHint
        )
        // Best-effort: bias decoding toward custom-vocabulary spellings. Empty
        // vocabulary or a missing tokenizer leaves decoding unchanged.
        let promptTokens = WhisperKitMeetingProviderMapping.vocabularyPrompt(vocabularyProvider())
            .flatMap { transcriber.promptTokens(for: $0) }
        let options = WhisperKitMeetingProviderMapping.decodingOptions(
            languageHint: normalizedLanguageHint,
            promptTokens: promptTokens
        )
        let results = try await transcriber.transcribe(audioPath: audioURL.path, decodeOptions: options)

        await progress(1.0)
        return WhisperKitMeetingProviderMapping.map(results, languageHint: normalizedLanguageHint)
    }

    private func loadIfNeeded() async throws -> any WhisperKitMeetingTranscribing {
        if let transcriber {
            return transcriber
        }
        let folder = resolveModelFolder()
        guard let folder, Self.isUsableLocalModelFolder(folder) else {
            throw MeetingTranscriptionProviderError.localModelUnavailable(folder?.path)
        }

        let loaded = try await loader(folder)
        transcriber = loaded
        return loaded
    }

    private static func isUsableLocalModelFolder(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        // Only the three CoreML models are required locally. The tokenizer is
        // NOT bundled in the downloaded variant — WhisperKit resolves it at load
        // time (see WhisperKitProvider's type doc); requiring tokenizer.json here
        // is what made transcription permanently unavailable.
        let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        return requiredModelNames.allSatisfy { modelName in
            let compiledModel = folder.appending(path: "\(modelName).mlmodelc")
            let packageModel = folder.appending(
                path: "\(modelName).mlpackage/Data/com.apple.CoreML/model.mlmodel"
            )
            return FileManager.default.fileExists(atPath: compiledModel.path)
                || FileManager.default.fileExists(atPath: packageModel.path)
        }
    }

}

enum WhisperKitMeetingProviderMapping {
    static func normalizedDecodingLanguage(from languageHint: String?) -> String? {
        TranscriptionLanguageHint.normalize(languageHint)
    }

    static func decodingOptions(languageHint: String?, promptTokens: [Int]? = nil) -> DecodingOptions {
        // `usePrefillPrompt` stays at WhisperKit's default (true) so the no-vocab
        // path is byte-identical to before (a `false` here would silently flip
        // `detectLanguage` on). Prompt tokens are prepended regardless when set.
        DecodingOptions(
            language: languageHint,
            withoutTimestamps: false,
            wordTimestamps: true,
            promptTokens: promptTokens
        )
    }

    /// Builds a single prompt string from the user's custom vocabulary, biasing
    /// the decoder toward the canonical replacement spellings (the form we want
    /// in the output). Returns `nil` for an empty vocabulary so decoding is left
    /// untouched.
    static func vocabularyPrompt(_ entries: [CustomVocabularyEntry]) -> String? {
        let terms =
            entries
            .filter(\.isUsable)
            .map { entry -> String in
                let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                return replacement.isEmpty
                    ? entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                    : replacement
            }
            .filter { $0.isEmpty == false }
        guard terms.isEmpty == false else { return nil }
        return terms.joined(separator: ", ")
    }

    static func map(
        _ results: [WhisperKitMeetingRawResult],
        languageHint: String?
    ) -> TranscriptionResult {
        let text =
            results
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let segments = results.flatMap { result in
            result.segments.compactMap { segment in
                TranscriptionTimingMapper.segment(
                    startSeconds: Double(segment.start),
                    endSeconds: Double(segment.end),
                    text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    words: segment.words.compactMap(mapWord)
                )
            }
        }
        let nonEmptySegments = segments.filter { !$0.text.isEmpty || !$0.words.isEmpty }
        let detectedLanguage =
            results.lazy.compactMap { TranscriptionLanguageHint.normalize($0.language) }.first
            ?? languageHint ?? "und"

        return TranscriptionResult(
            text: text,
            segments: nonEmptySegments,
            detectedLanguage: detectedLanguage
        )
    }

    static func mapWord(_ word: WhisperKitMeetingRawWord) -> TranscriptionWord? {
        TranscriptionTimingMapper.word(
            from: RawTranscriptionTiming(
                startSeconds: Double(word.start),
                endSeconds: Double(word.end),
                text: word.text
            )
        )
    }
}

extension WhisperKitMeetingProviderEngine {
    private func enter() async {
        if !busy {
            busy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
