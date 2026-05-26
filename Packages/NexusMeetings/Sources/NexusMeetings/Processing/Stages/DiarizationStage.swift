import FluidAudio
import Foundation

public struct DiarizationSegment: Sendable, Equatable {
    public let startMs: Int
    public let endMs: Int
    public let speakerID: String

    public init(startMs: Int, endMs: Int, speakerID: String) {
        self.startMs = startMs
        self.endMs = endMs
        self.speakerID = speakerID
    }
}

public protocol SortformerSession: Sendable {
    func diarize(audioURL: URL) async throws -> [DiarizationSegment]
}

public final class DiarizationStage: Sendable {
    private let sessionLoader: @Sendable () -> any SortformerSession

    public init(sessionLoader: @escaping @Sendable () -> any SortformerSession = { FluidAudioSortformerSession() }) {
        self.sessionLoader = sessionLoader
    }

    public func run(audioURL: URL) async throws -> [DiarizationSegment] {
        let session = sessionLoader()
        return try await session.diarize(audioURL: audioURL)
    }
}

public struct FluidAudioSortformerSession: SortformerSession {
    public init() {}

    public func diarize(audioURL: URL) async throws -> [DiarizationSegment] {
        let config = SortformerConfig.default
        let diarizer = SortformerDiarizer(config: config)
        let models = try await SortformerModels.loadFromHuggingFace(config: config)
        diarizer.initialize(models: models)

        let timeline = try diarizer.processComplete(audioFileURL: audioURL)
        return timeline.speakers.values.flatMap { speaker in
            speaker.finalizedSegments + speaker.tentativeSegments
        }
        .compactMap(Self.segment(from:))
        .sorted(by: Self.segmentSort)
    }

    static func segment(from segment: DiarizerSegment) -> DiarizationSegment? {
        guard
            let startMs = milliseconds(from: segment.startTime),
            let endMs = milliseconds(from: segment.endTime),
            endMs > startMs
        else {
            return nil
        }

        return DiarizationSegment(
            startMs: startMs,
            endMs: endMs,
            speakerID: "Speaker_\(segment.speakerIndex + 1)"
        )
    }

    static func segmentSort(_ lhs: DiarizationSegment, _ rhs: DiarizationSegment) -> Bool {
        if lhs.startMs == rhs.startMs {
            if lhs.endMs == rhs.endMs {
                return lhs.speakerID < rhs.speakerID
            }
            return lhs.endMs < rhs.endMs
        }
        return lhs.startMs < rhs.startMs
    }

    static func milliseconds(from seconds: Float) -> Int? {
        guard seconds.isFinite else { return nil }
        let milliseconds = Double(seconds) * 1_000
        guard milliseconds.isFinite else { return nil }
        let roundedMilliseconds = milliseconds.rounded()
        guard roundedMilliseconds < Double(Int.max), roundedMilliseconds > Double(Int.min) else { return nil }
        return Int(roundedMilliseconds)
    }
}
