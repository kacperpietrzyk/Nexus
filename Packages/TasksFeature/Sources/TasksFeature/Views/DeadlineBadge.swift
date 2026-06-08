import Foundation
import NexusUI

// MARK: - DeadlineBadgePresentation

/// Semantic urgency of a deadline, independent of its display tone. Two kinds
/// (`.missed`, `.today`) both render red (`.rose`) but are distinct facts, so
/// dedupe logic keys on this, not on `tone` or the human-readable label.
public enum DeadlineUrgency: Equatable, Sendable {
    case missed  // dayDelta < 0 — the deadline has already passed
    case today  // dayDelta == 0 — the deadline is today (more urgent than a slipped due)
    case upcoming  // dayDelta > 0 — a future deadline
}

public struct DeadlineBadgePresentation: Equatable, Sendable {
    public let label: String
    public let systemImage: String
    public let tone: NexusChipTone
    public let kind: DeadlineUrgency

    public init(
        label: String,
        systemImage: String = "flag.fill",
        tone: NexusChipTone,
        kind: DeadlineUrgency
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.kind = kind
    }
}

// MARK: - DeadlineBadgeFormatter

public enum DeadlineBadgeFormatter {
    public static func presentation(
        deadlineAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> DeadlineBadgePresentation? {
        guard let deadlineAt else { return nil }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDeadline = calendar.startOfDay(for: deadlineAt)
        let dayDelta = calendar.dateComponents([.day], from: startOfToday, to: startOfDeadline).day ?? 0

        if dayDelta < 0 {
            return DeadlineBadgePresentation(label: "deadline missed", tone: .rose, kind: .missed)
        }
        if dayDelta == 0 {
            return DeadlineBadgePresentation(label: "deadline today", tone: .rose, kind: .today)
        }

        // MP-2 accent burn-down: always .neutral regardless of 1…3 day window
        return DeadlineBadgePresentation(label: "deadline in \(dayDelta)d", tone: .neutral, kind: .upcoming)
    }
}
