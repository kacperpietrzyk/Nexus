import FluidAudio
import Foundation

public struct VADSpeechRange: Sendable, Equatable {
    public let startMs: Int
    public let endMs: Int

    public init(startMs: Int, endMs: Int) {
        self.startMs = startMs
        self.endMs = endMs
    }
}

public protocol SileroVADSession: Sendable {
    func detectSpeechRanges(audioURL: URL, durationMs: Int) async throws -> [VADSpeechRange]
}

public struct VADTrimOutput: Sendable, Equatable {
    public let speechRanges: [VADSpeechRange]
    public let headTrimMs: Int
    public let tailTrimMs: Int

    public init(speechRanges: [VADSpeechRange], headTrimMs: Int, tailTrimMs: Int) {
        self.speechRanges = speechRanges
        self.headTrimMs = headTrimMs
        self.tailTrimMs = tailTrimMs
    }
}

public final class VADTrimStage: Sendable {
    private let sileroLoader: @Sendable () -> any SileroVADSession

    public init(sileroLoader: @escaping @Sendable () -> any SileroVADSession = { FluidAudioSileroSession() }) {
        self.sileroLoader = sileroLoader
    }

    public func run(audioURL: URL, durationMs: Int) async throws -> VADTrimOutput {
        let clampedDurationMs = max(0, durationMs)
        let session = sileroLoader()
        let detectedRanges = try await session.detectSpeechRanges(
            audioURL: audioURL,
            durationMs: clampedDurationMs
        )
        let ranges = Self.sanitizedRanges(detectedRanges, durationMs: clampedDurationMs)
        let firstStart = ranges.first?.startMs ?? 0
        let lastEnd = ranges.last?.endMs ?? clampedDurationMs
        let headTrimMs = min(clampedDurationMs, max(0, firstStart))
        let tailTrimMs = min(clampedDurationMs, max(0, clampedDurationMs - lastEnd))

        return VADTrimOutput(
            speechRanges: ranges,
            headTrimMs: headTrimMs,
            tailTrimMs: tailTrimMs
        )
    }

    private static func sanitizedRanges(_ ranges: [VADSpeechRange], durationMs: Int) -> [VADSpeechRange] {
        let sortedRanges =
            ranges
            .map { range in
                let startMs = min(durationMs, max(0, range.startMs))
                let endMs = min(durationMs, max(0, range.endMs))

                return VADSpeechRange(startMs: startMs, endMs: endMs)
            }
            .filter { $0.endMs > $0.startMs }
            .sorted { lhs, rhs in
                if lhs.startMs == rhs.startMs {
                    return lhs.endMs < rhs.endMs
                }
                return lhs.startMs < rhs.startMs
            }

        return sortedRanges.reduce(into: []) { mergedRanges, range in
            guard let previous = mergedRanges.last else {
                mergedRanges.append(range)
                return
            }

            guard range.startMs <= previous.endMs else {
                mergedRanges.append(range)
                return
            }

            mergedRanges[mergedRanges.count - 1] = VADSpeechRange(
                startMs: previous.startMs,
                endMs: max(previous.endMs, range.endMs)
            )
        }
    }
}

public struct FluidAudioSileroSession: SileroVADSession {
    public init() {}

    public func detectSpeechRanges(audioURL: URL, durationMs: Int) async throws -> [VADSpeechRange] {
        let manager = try await VadManager()
        let results = try await manager.process(audioURL)
        let totalSamples = Self.totalSamples(durationMs: durationMs)
        let segments = await manager.segmentSpeech(from: results, totalSamples: totalSamples)

        return segments.compactMap { segment in
            guard
                let startMs = Self.milliseconds(from: segment.startTime),
                let endMs = Self.milliseconds(from: segment.endTime)
            else {
                return nil
            }

            return VADSpeechRange(
                startMs: startMs,
                endMs: endMs
            )
        }
    }

    static func totalSamples(durationMs: Int) -> Int {
        guard durationMs > 0 else { return 0 }
        let seconds = durationMs / 1_000
        let remainderMs = durationMs % 1_000
        let sampleRate = VadManager.sampleRate

        guard seconds <= Int.max / sampleRate else { return Int.max }
        let baseSamples = seconds * sampleRate
        let remainderSamples = remainderMs * sampleRate / 1_000
        guard baseSamples <= Int.max - remainderSamples else { return Int.max }

        return baseSamples + remainderSamples
    }

    static func milliseconds(from seconds: TimeInterval) -> Int? {
        guard seconds.isFinite else { return nil }
        let milliseconds = seconds * 1_000
        guard milliseconds.isFinite else { return nil }
        let roundedMilliseconds = milliseconds.rounded()
        guard roundedMilliseconds < Double(Int.max), roundedMilliseconds > Double(Int.min) else { return nil }
        return Int(roundedMilliseconds)
    }
}
