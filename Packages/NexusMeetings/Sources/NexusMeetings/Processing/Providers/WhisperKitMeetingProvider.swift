import Foundation
@preconcurrency import WhisperKit

public enum MeetingTranscriptionProviderError: Error, Equatable, Sendable {
    case localModelUnavailable(String?)
}

public final class WhisperKitMeetingProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    public let identifier = "whisperkit-large"

    private let engine: WhisperKitMeetingProviderEngine

    public init(localModelFolder: URL? = WhisperKitMeetingProvider.defaultLocalModelFolder()) {
        self.engine = WhisperKitMeetingProviderEngine(localModelFolder: localModelFolder)
    }

    init(localModelFolder: URL?, loader: @escaping WhisperKitMeetingProviderEngine.Loader) {
        self.engine = WhisperKitMeetingProviderEngine(localModelFolder: localModelFolder, loader: loader)
    }

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await engine.transcribe(audioURL: audioURL, languageHint: languageHint, progress: progress)
    }

    public static func defaultLocalModelFolder() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Nexus", directoryHint: .isDirectory)
            .appending(path: "WhisperKit", directoryHint: .isDirectory)
    }
}

protocol WhisperKitMeetingTranscribing: Sendable {
    func transcribe(audioPath: String, decodeOptions: DecodingOptions) async throws -> [WhisperKitMeetingRawResult]
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

    init(modelFolder: URL) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        self.whisperKit = try await WhisperKit(config)
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

    private let localModelFolder: URL?
    private let loader: Loader
    private var transcriber: (any WhisperKitMeetingTranscribing)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        localModelFolder: URL?,
        loader: @escaping Loader = { folder in
            try await LiveWhisperKitMeetingTranscriber(modelFolder: folder)
        }
    ) {
        self.localModelFolder = localModelFolder
        self.loader = loader
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
        let options = WhisperKitMeetingProviderMapping.decodingOptions(languageHint: normalizedLanguageHint)
        let results = try await transcriber.transcribe(audioPath: audioURL.path, decodeOptions: options)

        await progress(1.0)
        return WhisperKitMeetingProviderMapping.map(results, languageHint: normalizedLanguageHint)
    }

    private func loadIfNeeded() async throws -> any WhisperKitMeetingTranscribing {
        if let transcriber {
            return transcriber
        }
        guard let localModelFolder, Self.isUsableLocalModelFolder(localModelFolder) else {
            throw MeetingTranscriptionProviderError.localModelUnavailable(localModelFolder?.path)
        }

        let loaded = try await loader(localModelFolder)
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

        let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        let hasRequiredModels = requiredModelNames.allSatisfy { modelName in
            let compiledModel = folder.appending(path: "\(modelName).mlmodelc")
            let packageModel = folder.appending(
                path: "\(modelName).mlpackage/Data/com.apple.CoreML/model.mlmodel"
            )
            return FileManager.default.fileExists(atPath: compiledModel.path)
                || FileManager.default.fileExists(atPath: packageModel.path)
        }
        let hasLocalTokenizer = FileManager.default.fileExists(
            atPath: folder.appending(path: "tokenizer.json").path
        )

        return hasRequiredModels && hasLocalTokenizer
    }

}

enum WhisperKitMeetingProviderMapping {
    static func normalizedDecodingLanguage(from languageHint: String?) -> String? {
        TranscriptionLanguageHint.normalize(languageHint)
    }

    static func decodingOptions(languageHint: String?) -> DecodingOptions {
        DecodingOptions(
            language: languageHint,
            withoutTimestamps: false,
            wordTimestamps: true
        )
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
