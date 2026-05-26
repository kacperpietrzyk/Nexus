import Foundation

public final class MergeStage: Sendable {
    public init() {}

    public func merge(
        me: TranscriptionResult,
        others: TranscriptionResult,
        othersDiarization: [DiarizationSegment]
    ) -> [MeetingSpeakerSegment] {
        let meSegments = me.segments.map {
            MeetingSpeakerSegment(startMs: $0.startMs, endMs: $0.endMs, speaker: "Me", text: $0.text)
        }
        let othersSegments = others.segments.map { seg -> MeetingSpeakerSegment in
            let speaker =
                othersDiarization
                .first(where: { $0.startMs <= seg.startMs && $0.endMs >= seg.endMs })?.speakerID
                ?? bestOverlapSpeaker(for: seg, diarization: othersDiarization)
                ?? "Speaker_1"

            return MeetingSpeakerSegment(
                startMs: seg.startMs,
                endMs: seg.endMs,
                speaker: speaker,
                text: seg.text
            )
        }

        return (meSegments + othersSegments).sorted(by: segmentSort)
    }

    public func renderLinear(_ segments: [MeetingSpeakerSegment]) -> String {
        segments.map { seg in
            let timestamp = formatTimestamp(ms: seg.startMs)
            return "[\(timestamp)] \(seg.speaker)\n\(seg.text)\n"
        }.joined(separator: "\n")
    }

    private func bestOverlapSpeaker(
        for seg: TranscriptionSegment,
        diarization: [DiarizationSegment]
    ) -> String? {
        let bestMatch = diarization.max { lhs, rhs in
            let lhsOverlap = overlap(seg, lhs)
            let rhsOverlap = overlap(seg, rhs)
            if lhsOverlap == rhsOverlap {
                return diarizationSort(lhs, rhs)
            }
            return lhsOverlap < rhsOverlap
        }
        guard let bestMatch, overlap(seg, bestMatch) > 0 else { return nil }
        return bestMatch.speakerID
    }

    private func overlap(_ seg: TranscriptionSegment, _ diar: DiarizationSegment) -> Int {
        max(0, min(seg.endMs, diar.endMs) - max(seg.startMs, diar.startMs))
    }

    private func segmentSort(_ lhs: MeetingSpeakerSegment, _ rhs: MeetingSpeakerSegment) -> Bool {
        if lhs.startMs == rhs.startMs {
            if lhs.endMs == rhs.endMs {
                if lhs.speaker == rhs.speaker {
                    return lhs.text < rhs.text
                }
                return lhs.speaker < rhs.speaker
            }
            return lhs.endMs < rhs.endMs
        }
        return lhs.startMs < rhs.startMs
    }

    private func diarizationSort(_ lhs: DiarizationSegment, _ rhs: DiarizationSegment) -> Bool {
        if lhs.startMs == rhs.startMs {
            if lhs.endMs == rhs.endMs {
                return lhs.speakerID < rhs.speakerID
            }
            return lhs.endMs < rhs.endMs
        }
        return lhs.startMs < rhs.startMs
    }

    private func formatTimestamp(ms: Int) -> String {
        let totalSeconds = ms / 1_000
        let h = totalSeconds / 3_600
        let m = (totalSeconds % 3_600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
