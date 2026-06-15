import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Pure presentation mapping for the Liquid task row (`TaskRowView`):
/// deterministic tag accents, visible-tag capping, the trailing due metadata
/// text, and tone→color bridging for pills. Extracted as pure helpers so the
/// row's visual contract is unit-testable without driving SwiftUI — same
/// precedent as `DueChipFormatter` / `TaskListEmptyState`.
enum TaskRowLiquidStyle {

    // MARK: Tag accents

    /// The quiet accents a user tag may take. Red and amber are deliberately
    /// absent — they are spent on the temporal axis (overdue / deadline), so a
    /// tag can never impersonate urgency.
    static let tagAccents: [Color] = [
        DS.ColorToken.accentBlue,
        DS.ColorToken.accentCyan,
        DS.ColorToken.accentPurple,
        DS.ColorToken.accentGreen,
        DS.ColorToken.accentPink,
    ]

    /// Stable palette index for a tag. FNV-1a over UTF-8 — `String.hashValue`
    /// is per-process seeded and would reshuffle tag colors every launch.
    static func tagAccentIndex(for tag: String, paletteCount: Int = tagAccents.count) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in tag.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(paletteCount))
    }

    static func tagAccent(for tag: String) -> Color {
        tagAccents[tagAccentIndex(for: tag)]
    }

    // MARK: Tag capping

    /// At most `cap` tag pills render per row; the rest collapse into a real
    /// "+N" count (no tags are invented and none silently dropped).
    static func visibleTags(_ tags: [String], cap: Int = 2) -> (visible: [String], overflow: Int) {
        guard tags.count > cap else { return (tags, 0) }
        return (Array(tags.prefix(cap)), tags.count - cap)
    }

    // MARK: Due metadata

    /// Urgency role of the trailing due text; the row maps roles onto DS color
    /// tokens (overdue → danger, today → blue, later → tertiary ink).
    enum DueRole: Equatable {
        case overdue
        case today
        case upcoming
    }

    /// Trailing due metadata: plain text, not a chip — the reference rows
    /// carry the due date as quiet right-aligned metadata, with overdue as
    /// the single loud token.
    static func dueMetadata(for label: DueChipFormatter.DueChipLabel) -> (text: String, role: DueRole)? {
        switch label {
        case .noDate:
            return nil
        case .overdue(let daysLate):
            return ("\(daysLate)d late", .overdue)
        case .today(let timeOfDay):
            return (timeOfDay.map { "Today \($0)" } ?? "Today", .today)
        case .tomorrow(let timeOfDay):
            return (timeOfDay.map { "Tomorrow \($0)" } ?? "Tomorrow", .upcoming)
        case .future(let date, let timeOfDay):
            return (timeOfDay.map { "\(date) \($0)" } ?? date, .upcoming)
        }
    }

    static func dueColor(for role: DueRole) -> Color {
        switch role {
        case .overdue: return DS.ColorToken.statusDanger
        case .today: return DS.ColorToken.accentBlue
        case .upcoming: return DS.ColorToken.textTertiary
        }
    }

    // MARK: Priority

    /// Short row-pill label; `nil` omits the pill entirely (no-priority rows
    /// stay quiet). Colors reuse `TopPrioritiesCard.color(for:)` so the list
    /// and the Today card cannot drift apart.
    static func priorityLabel(for priority: TaskPriority) -> String? {
        switch priority {
        case .high: return "High"
        case .medium: return "Med"
        case .low: return "Low"
        case .none: return nil
        }
    }

    // MARK: Chip-tone bridge

    /// Bridges the legacy `NexusChipTone` carried by `DeadlineBadgePresentation`
    /// (and the subtask/blocks chips) onto DS accents, so formatters stay
    /// untouched while the row renders Liquid pills.
    static func pillColor(for tone: NexusChipTone) -> Color {
        switch tone {
        case .accent: return DS.ColorToken.accentPrimary
        case .neutral: return DS.ColorToken.statusNeutral
        case .rose, .negative: return DS.ColorToken.statusDanger
        case .warning: return DS.ColorToken.statusWarning
        case .positive: return DS.ColorToken.statusSuccess
        }
    }
}

// MARK: - Liquid checkbox state

/// Three-state circle checkbox for the Liquid task row. Snoozed renders as a
/// dashed ring (the "paused" idiom) — distinct from both open and done.
/// Module-scope + exhaustive so a new `TaskStatus` case is a compile error.
enum LiquidTaskCheckboxState: Equatable {
    case open
    case done
    case snoozed
}

func liquidCheckboxState(for status: TaskStatus) -> LiquidTaskCheckboxState {
    switch status {
    case .open: return .open
    case .done: return .done
    case .snoozed: return .snoozed
    }
}

/// 14 pt Liquid circle checkbox (03_COMPONENTS.md §TaskRow): open = thin ring,
/// snoozed = dashed ring, done = accent fill + checkmark. The button wrapper in
/// `TaskRowView` owns hit-target sizing and accessibility.
struct LiquidTaskCheckbox: View {
    let state: LiquidTaskCheckboxState
    let isHovering: Bool

    var body: some View {
        ZStack {
            switch state {
            case .open:
                Circle()
                    .stroke(
                        isHovering ? DS.ColorToken.textSecondary : DS.ColorToken.textTertiary,
                        lineWidth: 1.5
                    )
            case .snoozed:
                Circle()
                    .stroke(
                        DS.ColorToken.textTertiary,
                        style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5])
                    )
            case .done:
                Circle()
                    .fill(DS.ColorToken.accentPrimary)
                Image(systemName: "checkmark")
                    // 8 pt glyph inside the 14 pt circle — same calibration as
                    // NexusUI's LiquidTaskRow checkbox.
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.ColorToken.textPrimary)
            }
        }
        .frame(width: 14, height: 14)
        .animation(DS.Motion.press, value: state)
    }
}
