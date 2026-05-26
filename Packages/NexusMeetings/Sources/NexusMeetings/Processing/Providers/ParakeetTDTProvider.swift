import FluidAudio
import Foundation

public final class ParakeetTDTProvider: MeetingTranscriptionProvider, @unchecked Sendable {
    public let identifier = "parakeet-tdt-v3"

    private let engine: ParakeetTDTProviderEngine

    public init() {
        self.engine = ParakeetTDTProviderEngine()
    }

    init(engine: ParakeetTDTProviderEngine) {
        self.engine = engine
    }

    public func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await engine.transcribe(audioURL: audioURL, languageHint: languageHint, progress: progress)
    }
}

actor ParakeetTDTProviderEngine {
    typealias Loader = @Sendable (DownloadUtils.ProgressHandler?) async throws -> AsrModels

    private let loader: Loader
    private var manager: AsrManager?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        loader: @escaping Loader = { progressHandler in
            try await AsrModels.downloadAndLoad(
                version: .v3,
                encoderPrecision: .int8,
                progressHandler: progressHandler
            )
        }
    ) {
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
        let manager = try await loadIfNeeded()
        await progress(0.65)

        let decoderLayerCount = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let normalizedLanguageHint = TranscriptionLanguageHint.normalize(languageHint)
        let language = normalizedLanguageHint.flatMap(Language.init(rawValue:))
        let result = try await manager.transcribe(audioURL, decoderState: &decoderState, language: language)

        await progress(1.0)
        return ParakeetTDTProviderMapping.map(
            text: result.text,
            duration: result.duration,
            tokenTimings: result.tokenTimings?.map {
                RawTranscriptionTiming(
                    startSeconds: $0.startTime,
                    endSeconds: $0.endTime,
                    text: $0.token
                )
            } ?? [],
            detectedLanguage: language?.rawValue ?? "und"
        )
    }

    private func loadIfNeeded() async throws -> AsrManager {
        if let manager {
            return manager
        }

        let models = try await loader(nil)
        let loadedManager = AsrManager(config: .default, models: models)
        manager = loadedManager
        return loadedManager
    }

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

enum ParakeetTDTProviderMapping {
    static func map(
        text: String,
        duration: TimeInterval,
        tokenTimings: [RawTranscriptionTiming],
        detectedLanguage: String
    ) -> TranscriptionResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = coalescedWords(from: tokenTimings)

        let segments: [TranscriptionSegment]
        if let firstWord = words.first, let lastWord = words.last {
            segments = [
                TranscriptionSegment(
                    startMs: firstWord.startMs,
                    endMs: lastWord.endMs,
                    text: trimmedText,
                    words: words
                )
            ].filter { $0.endMs > $0.startMs }
        } else if let fallbackSegment = TranscriptionTimingMapper.segment(
            startSeconds: 0,
            endSeconds: duration,
            text: trimmedText
        ) {
            segments = [fallbackSegment]
        } else {
            segments = []
        }

        return TranscriptionResult(
            text: trimmedText,
            segments: segments,
            detectedLanguage: detectedLanguage
        )
    }

    static func coalescedWords(from tokenTimings: [RawTranscriptionTiming]) -> [TranscriptionWord] {
        var words: [TranscriptionWord] = []
        var currentText = ""
        var currentStartSeconds: Double?
        var currentEndSeconds: Double?

        func flushCurrentWord() {
            guard let startSeconds = currentStartSeconds,
                let endSeconds = currentEndSeconds,
                let word = TranscriptionTimingMapper.word(
                    from: RawTranscriptionTiming(
                        startSeconds: startSeconds,
                        endSeconds: endSeconds,
                        text: currentText
                    )
                )
            else {
                currentText = ""
                currentStartSeconds = nil
                currentEndSeconds = nil
                return
            }

            words.append(word)
            currentText = ""
            currentStartSeconds = nil
            currentEndSeconds = nil
        }

        for timing in tokenTimings {
            let rawToken = timing.text
            let startsNewWord = rawToken.hasPrefix("▁")
            if startsNewWord {
                flushCurrentWord()
            }

            guard let rawStartMs = TranscriptionTimingMapper.milliseconds(from: timing.startSeconds),
                let rawEndMs = TranscriptionTimingMapper.milliseconds(from: timing.endSeconds)
            else {
                continue
            }

            let startMs = max(0, rawStartMs)
            let endMs = max(0, rawEndMs)
            guard endMs > startMs else { continue }

            let piece =
                rawToken
                .replacingOccurrences(of: "▁", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            if startsNewWord || currentStartSeconds == nil {
                currentText = piece
                currentStartSeconds = timing.startSeconds
                currentEndSeconds = timing.endSeconds
            } else {
                currentText += piece
                currentEndSeconds = timing.endSeconds
            }
        }

        flushCurrentWord()
        return words
    }
}
