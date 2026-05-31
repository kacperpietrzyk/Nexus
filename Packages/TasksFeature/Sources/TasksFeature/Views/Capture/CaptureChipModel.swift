import NexusCore
import NexusUI
import SwiftUI

/// Shared capture-chip model: emit-order + predicates + per-chip formatters +
/// the chip view-builder. Single source of truth consumed by both the iOS
/// `CaptureChipsView` and the Mac `CapturePane.macCapturePanel` (MP-6.4 — the
/// formerly byte-mirrored fork is now one type). Pure functions over inputs;
/// `now` is a parameter so each call-site keeps its exact current behavior
/// (iOS passes the injected `CaptureChipsView.now`; Mac passes `.now`).
enum CaptureChipModel {

    /// Ordered chip list from a `ParseResult`. Emit order:
    /// date → timeRange → priority → tags → recurrence → lowConfidence.
    static func chips(for result: ParseResult, now: Date) -> [(icon: String?, label: String)] {
        var chips: [(icon: String?, label: String)] = []
        if result.dueAt != nil || result.startAt != nil {
            chips.append((icon: "calendar", label: formatDate(result, now: now)))
        }
        if let timeRange = formatTimeRange(result) {
            chips.append((icon: "clock", label: timeRange))
        }
        if let priority = result.priority {
            // Empty-label-priority quirk preserved: priorityLabel(.none) == "",
            // so a `.none` priority renders the exclamationmark icon + an empty
            // Text label. No `label != ""` guard — the quirk is mirror-locked.
            chips.append((icon: "exclamationmark", label: priorityLabel(priority)))
        }
        for tag in result.tags {
            chips.append((icon: nil, label: "#\(tag)"))
        }
        if result.recurrence != nil {
            chips.append((icon: "repeat", label: "Repeats"))
        }
        if result.confidence < 0.7 && result.dueAt == nil && result.recurrence == nil {
            chips.append((icon: "questionmark.circle", label: "Low confidence"))
        }
        return chips
    }

    /// Per-chip render (oracle `chip(_:_:)` idiom). `block -> Glass.surface2`
    /// stopgap: LabPalette.block(0.055) rounds to the adjacent anchored rung
    /// surface2(0.06); delta is sub-perceptual white-on-dark. Documented
    /// stopgap, not a raw Color literal and not a new token (§8 precedent).
    static func chip(icon: String?, label: String) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            Text(label)
                .font(Font.custom("IBMPlexMono-Medium", size: 11))
                .foregroundStyle(NexusColor.Text.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(NexusColor.Background.control, in: Capsule())
    }

    static func formatDate(_ result: ParseResult, now: Date) -> String {
        guard let dueAt = result.dueAt else {
            if let startAt = result.startAt {
                return startAt.formatted(date: .omitted, time: .shortened)
            }
            return ""
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let dayDelta =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: dueAt)
            ).day ?? 0
        let timeOfDay = result.startAt?.formatted(date: .omitted, time: .shortened)
        let prefix: String
        switch dayDelta {
        case 0: prefix = "Today"
        case 1: prefix = "Tomorrow"
        default: prefix = dueAt.formatted(date: .abbreviated, time: .omitted)
        }
        return [prefix, timeOfDay].compactMap { $0 }.joined(separator: " ")
    }

    static func formatTimeRange(_ result: ParseResult) -> String? {
        guard let startAt = result.startAt, let endAt = result.endAt else { return nil }
        let start = startAt.formatted(date: .omitted, time: .shortened)
        let end = endAt.formatted(date: .omitted, time: .shortened)
        return "\(start) -> \(end)"
    }

    static func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .high: return "P1"
        case .medium: return "P2"
        case .low: return "P3"
        case .none: return ""
        }
    }
}
