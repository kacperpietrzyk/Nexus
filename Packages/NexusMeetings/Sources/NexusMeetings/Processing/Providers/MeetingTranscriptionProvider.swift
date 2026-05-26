import Foundation

public struct TranscriptionWord: Sendable, Codable, Equatable {
    public let startMs: Int
    public let endMs: Int
    public let text: String

    public init(startMs: Int, endMs: Int, text: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
    }
}

public struct TranscriptionSegment: Sendable, Codable, Equatable {
    public let startMs: Int
    public let endMs: Int
    public let text: String
    public let words: [TranscriptionWord]

    public init(startMs: Int, endMs: Int, text: String, words: [TranscriptionWord] = []) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
    }
}

public struct TranscriptionResult: Sendable, Codable, Equatable {
    public let text: String
    public let segments: [TranscriptionSegment]
    public let detectedLanguage: String

    public init(text: String, segments: [TranscriptionSegment], detectedLanguage: String) {
        self.text = text
        self.segments = segments
        self.detectedLanguage = detectedLanguage
    }
}

public protocol MeetingTranscriptionProvider: Sendable {
    var identifier: String { get }

    func transcribe(
        audioURL: URL,
        languageHint: String?,
        progress: @MainActor @Sendable (Double) -> Void
    ) async throws -> TranscriptionResult
}

enum TranscriptionLanguageHint {
    private static let supportedBaseCodes: Set<String> = [
        "be", "bg", "bs", "cs", "de", "en", "es", "fr", "hr", "it", "pl", "pt", "ro", "ru", "sk",
        "sl", "sr", "uk",
    ]

    static func normalize(_ hint: String?) -> String? {
        guard let hint else { return nil }

        let normalized =
            hint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        guard let baseCode = normalized.split(separator: "-").first.map(String.init),
            supportedBaseCodes.contains(baseCode)
        else {
            return nil
        }

        return baseCode
    }
}

struct RawTranscriptionTiming: Sendable, Equatable {
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}

enum TranscriptionTimingMapper {
    static func word(from timing: RawTranscriptionTiming) -> TranscriptionWord? {
        let text = timing.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        guard let rawStartMs = milliseconds(from: timing.startSeconds),
            let rawEndMs = milliseconds(from: timing.endSeconds)
        else {
            return nil
        }

        let startMs = max(0, rawStartMs)
        let endMs = max(0, rawEndMs)
        guard endMs > startMs else { return nil }

        return TranscriptionWord(startMs: startMs, endMs: endMs, text: text)
    }

    static func segment(
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        words: [TranscriptionWord] = []
    ) -> TranscriptionSegment? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !words.isEmpty else { return nil }

        guard let rawStartMs = milliseconds(from: startSeconds),
            let rawEndMs = milliseconds(from: endSeconds)
        else {
            return nil
        }

        let startMs = max(0, rawStartMs)
        let endMs = max(0, rawEndMs)
        guard endMs > startMs else { return nil }

        return TranscriptionSegment(startMs: startMs, endMs: endMs, text: text, words: words)
    }

    static func milliseconds(from seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }

        let scaled = seconds * 1_000
        let rounded = scaled.rounded()
        guard rounded.isFinite,
            rounded >= Double(Int.min),
            rounded < Double(Int.max)
        else {
            return nil
        }

        return Int(rounded)
    }
}
