import NexusCore
import NexusUI
import SwiftUI

/// Filter-row rules for the Notes graph. Color/glyph delegate to the shared
/// `KnowledgeGraphStyle.standard` so the filter pills read the same kind→accent/
/// glyph language as the graph nodes themselves (and the Meetings sheet).
enum GraphStyle {
    /// Stable display order for the filter pill row.
    static let filterableKinds: [ItemKind] = [
        .note, .task, .project, .meeting, .person, .label, .cycle,
    ]

    static func glyph(for kind: ItemKind) -> String { KnowledgeGraphStyle.glyph(for: kind) }

    static func accent(for kind: ItemKind) -> Color { KnowledgeGraphStyle.accent(for: kind) }

    static func displayTitle(_ title: String, maxLength: Int = 28) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}
