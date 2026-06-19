import NexusCore
import SwiftUI

/// Host-provided visual mapping for graph nodes. Kept host-provided so NexusUI
/// does not encode per-feature `ItemKind` semantics.
public struct KnowledgeGraphStyle {
    public let color: (ItemKind) -> Color
    public let icon: (ItemKind) -> String

    public init(color: @escaping (ItemKind) -> Color, icon: @escaping (ItemKind) -> String) {
        self.color = color
        self.icon = icon
    }
}
