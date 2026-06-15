import Foundation
import NexusCore

/// Pure, deterministic Markdown renderer for a meeting's export (C1 —
/// Circleback parity). Determinism: dates go through
/// `MarkdownFrontmatterCoder.dateFormatter` (UTC ISO8601, no locale), transcript
/// timestamps are computed from integer milliseconds, and section order is
/// fixed (Summary → Action items → Transcript). Empty sections are omitted —
/// no invented copy. No UIKit/AppKit, no SwiftData: callers snapshot stored
/// rows into plain values first (see `Meeting+MarkdownExport`).
public enum MeetingMarkdownRenderer {

    /// Value snapshot of an action-item `TaskItem` — keeps `body` pure.
    public struct ActionItem: Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let isDone: Bool

        public init(id: UUID, title: String, isDone: Bool) {
            self.id = id
            self.title = title
            self.isDone = isDone
        }
    }

    // MARK: - Frontmatter

    /// Meeting-specific frontmatter, appended after the base `MarkdownDocument`
    /// fields. Attendees are participants with a non-empty display name — the
    /// same rule `LiquidMeetingsModel.attendees` uses for the detail header.
    /// `durationSec` rides as a string: `FrontmatterValue` has no integer case.
    public static func frontmatterExtras(
        startedAt: Date,
        durationSec: Int,
        participants: [MeetingParticipant],
        calendarEventID: String?
    ) -> [(String, FrontmatterValue)] {
        let names =
            participants
            .map { $0.displayName.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return [
            ("startedAt", .date(startedAt)),
            ("durationSec", .string(String(durationSec))),
            ("attendees", .list(names.map(FrontmatterValue.string))),
            ("calendarEventID", calendarEventID.map(FrontmatterValue.string) ?? .none),
        ]
    }

    // MARK: - Body

    /// `## Summary` (parsed structured sections) + `## Action items` (checkbox
    /// list with task ids) + `## Transcript` (speaker-attributed, timestamped).
    public static func body(
        summary: MeetingSummarySections,
        actionItems: [ActionItem],
        segments: [MeetingSpeakerSegment],
        participants: [MeetingParticipant],
        transcriptText: String
    ) -> String {
        [
            summarySection(summary),
            actionItemsSection(actionItems),
            transcriptSection(
                segments: segments, participants: participants, transcriptText: transcriptText),
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    // MARK: - Sections

    /// Overview paragraph, then `### Decisions`, then each remaining parsed
    /// section — the same structure the Overview tab renders.
    private static func summarySection(_ summary: MeetingSummarySections) -> String? {
        var parts: [String] = []
        if let overview = summary.overview, !overview.isEmpty {
            parts.append(overview)
        }
        if !summary.decisions.isEmpty {
            parts.append("### Decisions\n\n" + bulletList(summary.decisions))
        }
        for section in summary.extraSections {
            parts.append("### \(section.title)\n\n" + bulletList(section.items))
        }
        guard !parts.isEmpty else { return nil }
        return "## Summary\n\n" + parts.joined(separator: "\n\n")
    }

    private static func actionItemsSection(_ items: [ActionItem]) -> String? {
        guard !items.isEmpty else { return nil }
        let lines = items.map { item in
            "- [\(item.isDone ? "x" : " ")] \(item.title) (task:\(item.id.uuidString))"
        }
        return "## Action items\n\n" + lines.joined(separator: "\n")
    }

    /// Speaker-attributed timestamped lines; diarized tokens are substituted
    /// with user-assigned display names (`MergeStage.displayNameMap` rule).
    /// Falls back to the raw linear transcript when no segments exist (e.g.
    /// Circleback imports carry only `transcriptText`).
    private static func transcriptSection(
        segments: [MeetingSpeakerSegment],
        participants: [MeetingParticipant],
        transcriptText: String
    ) -> String? {
        if !segments.isEmpty {
            let names = MergeStage.displayNameMap(participants)
            let lines = segments.map { segment in
                "- [\(timestamp(ms: segment.startMs))] "
                    + "\(names[segment.speaker] ?? segment.speaker): \(segment.text)"
            }
            return "## Transcript\n\n" + lines.joined(separator: "\n")
        }
        let raw = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return "## Transcript\n\n" + raw
    }

    private static func bulletList(_ items: [String]) -> String {
        items.map { "- \($0)" }.joined(separator: "\n")
    }

    /// `HH:MM:SS` from integer milliseconds — same shape as
    /// `MergeStage.renderLinear`'s timestamps.
    private static func timestamp(ms: Int) -> String {
        let totalSeconds = ms / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
