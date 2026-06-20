import NexusCore
import SwiftUI

/// Host-provided visual mapping for graph nodes. Kept host-provided so NexusUI
/// does not encode per-feature `ItemKind` semantics — but `.standard` gives every
/// consumer one shared kind→accent/glyph language so the same entity reads the
/// same color in the Meetings sheet and the Notes graph alike.
public struct KnowledgeGraphStyle: Sendable {
    public let color: @Sendable (ItemKind) -> Color
    public let icon: @Sendable (ItemKind) -> String

    public init(
        color: @escaping @Sendable (ItemKind) -> Color,
        icon: @escaping @Sendable (ItemKind) -> String
    ) {
        self.color = color
        self.icon = icon
    }

    /// The canonical knowledge-graph look. One accent per kind, drawn from the
    /// Liquid palette so each kind is scannable; glyphs mirror the in-app icons.
    public static let standard = KnowledgeGraphStyle(color: accent(for:), icon: glyph(for:))

    public static func accent(for kind: ItemKind) -> Color {
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

    public static func glyph(for kind: ItemKind) -> String {
        switch kind {
        case .note: return "doc.text"
        case .task: return "checkmark.circle"
        case .project: return "folder"
        case .meeting: return "person.2"
        case .person: return "person.crop.circle"
        case .label: return "tag"
        case .cycle: return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }
}
