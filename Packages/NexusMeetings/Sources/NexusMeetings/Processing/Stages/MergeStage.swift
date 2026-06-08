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
            // A fully-containing diarization turn yields the maximal possible
            // overlap, so `bestOverlapSpeaker` already selects it — and does so
            // deterministically. Picking `first(where: containment)` separately
            // would let array order decide between two turns that both contain the
            // segment (ME3); fold it into the single deterministic selection.
            let speaker = bestOverlapSpeaker(for: seg, diarization: othersDiarization) ?? "Speaker_1"

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
        renderLinear(segments, participants: [])
    }

    /// Renders the linear transcript, substituting each segment's diarized
    /// `Speaker_N` token for the user-assigned `displayName` when a participant
    /// mapping exists (spec §5). A speaker with no mapping — or whose `displayName`
    /// is still the auto-generated `speakerID` placeholder — renders the raw token,
    /// matching the labeling convention used across the module
    /// (`distinctParticipantNames`, `MeetingPeopleLinker`).
    public func renderLinear(
        _ segments: [MeetingSpeakerSegment],
        participants: [MeetingParticipant]
    ) -> String {
        let nameBySpeaker = Self.displayNameMap(participants)
        return segments.map { seg in
            let timestamp = formatTimestamp(ms: seg.startMs)
            let label = nameBySpeaker[seg.speaker] ?? seg.speaker
            return "[\(timestamp)] \(label)\n\(seg.text)\n"
        }.joined(separator: "\n")
    }

    /// Returns only the segments belonging to `speaker` (spec §6). A segment
    /// matches when its raw diarized token (`Speaker_N`, `Me`) equals the filter,
    /// OR when the user-assigned `displayName` for that token equals it — both
    /// compared case/diacritic-insensitively so "alice" finds "Alíce". Powers the
    /// speaker-aware search and `meetings.get_transcript` speaker filter; the raw
    /// branch covers `"Me"`, which never has a participant entry. A pure value
    /// function so it is trivially testable.
    public static func segments(
        _ segments: [MeetingSpeakerSegment],
        forSpeaker speaker: String,
        participants: [MeetingParticipant]
    ) -> [MeetingSpeakerSegment] {
        let nameBySpeaker = displayNameMap(participants)
        return segments.filter { segment in
            if matches(segment.speaker, speaker) { return true }
            if let name = nameBySpeaker[segment.speaker], matches(name, speaker) { return true }
            return false
        }
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Maps `speakerID -> displayName` for participants the user genuinely named
    /// (skips placeholders left at their `speakerID`). Last write wins on a
    /// duplicate `speakerID`, mirroring `TranscriptViewModel.rename`'s upsert.
    static func displayNameMap(_ participants: [MeetingParticipant]) -> [String: String] {
        var map: [String: String] = [:]
        for participant in participants {
            let name = participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, name != participant.speakerID else { continue }
            map[participant.speakerID] = name
        }
        return map
    }

    /// Picks the diarization turn that best labels `seg`: largest temporal overlap
    /// wins, ties broken deterministically by earliest start, then earliest end,
    /// then `speakerID`. Returns nil when no turn overlaps at all.
    private func bestOverlapSpeaker(
        for seg: TranscriptionSegment,
        diarization: [DiarizationSegment]
    ) -> String? {
        diarization
            .filter { overlap(seg, $0) > 0 }
            .min { lhs, rhs in
                let lhsOverlap = overlap(seg, lhs)
                let rhsOverlap = overlap(seg, rhs)
                if lhsOverlap != rhsOverlap { return lhsOverlap > rhsOverlap }
                if lhs.startMs != rhs.startMs { return lhs.startMs < rhs.startMs }
                if lhs.endMs != rhs.endMs { return lhs.endMs < rhs.endMs }
                return lhs.speakerID < rhs.speakerID
            }?
            .speakerID
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

    private func formatTimestamp(ms: Int) -> String {
        let totalSeconds = ms / 1_000
        let h = totalSeconds / 3_600
        let m = (totalSeconds % 3_600) / 60
        let s = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
