import NexusCore
import NexusUI
import SwiftUI

/// Visual rules for graph nodes. Glyphs mirror `NexusUI.ItemRow.iconName(for:)`;
/// accents use the Liquid design-system palette so each graph kind is scannable.
enum GraphStyle {
    /// Stable display order for the filter pill row.
    static let filterableKinds: [ItemKind] = [
        .note, .task, .project, .meeting, .person, .label, .cycle,
    ]

    static func glyph(for kind: ItemKind) -> String {
        switch kind {
        case .note: return "doc.text"
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .meeting: return "person.2"
        case .person: return "person.crop.circle"
        case .label: return "tag"
        case .cycle: return "arrow.triangle.2.circlepath"
        case .section: return "square.split.2x1"
        case .savedFilter: return "line.3.horizontal.decrease.circle"
        case .debug: return "ladybug"
        case .agentMemory: return "brain.head.profile"
        case .scheduledBlock: return "calendar.badge.clock"
        case .attachment: return "paperclip"
        case .organization: return "building.2"
        }
    }

    static func accent(for kind: ItemKind) -> Color {
        switch kind {
        case .note: return DS.ColorToken.accentBlue
        case .task: return DS.ColorToken.accentGreen
        case .project: return DS.ColorToken.accentPurple
        case .meeting: return DS.ColorToken.accentAmber
        case .person: return DS.ColorToken.accentPink
        case .label: return DS.ColorToken.accentCyan
        case .cycle: return DS.ColorToken.accentOrange
        default: return DS.ColorToken.textTertiary
        }
    }

    /// 5 pt base, sqrt(degree) growth, capped at 14 pt.
    static func nodeRadius(degree: Int) -> CGFloat {
        min(14, 5 + 1.5 * CGFloat(Double(max(0, degree)).squareRoot()))
    }

    static func displayTitle(_ title: String, maxLength: Int = 28) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}
