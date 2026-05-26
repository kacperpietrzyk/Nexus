import NexusCore
import SwiftUI

/// Generic Linkable row — title + kind chip + relative timestamp.
/// Used by lists, search results, backlinks panel, command palette results.
public struct ItemRow: View {
    public let title: String
    public let kind: ItemKind
    public let updatedAt: Date
    public let maxTitleLength: Int

    public init(item: any Linkable, maxTitleLength: Int = 80) {
        self.title = item.title
        self.kind = item.kind
        self.updatedAt = item.updatedAt
        self.maxTitleLength = maxTitleLength
    }

    public var displayTitle: String {
        guard title.count > maxTitleLength else { return title }
        let trimmed = title.prefix(maxTitleLength)
        return trimmed + "…"
    }

    /// Flat LabKit row resting background — `.clear`. LabKit content rows
    /// carry no per-row fill or divider (separation is spacing); a hover
    /// fill, if a surface wants one, is layered by that surface in
    /// MP-2…MP-5, not baked into this generic read-only row.
    internal var rowBackgroundColor: Color { .clear }

    public var body: some View {
        // LabKit `LabRowView` flat treatment, status-glyph-free (ItemRow is
        // generic over all ItemKinds and has no status concept).
        HStack(spacing: 12) {
            NexusChip(kind.displayName, systemImage: Self.iconName(for: kind), tone: Self.chipTone(for: kind))
            Text(displayTitle)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(updatedAt, style: .relative)
                .nexusType(.caption)
                .monospacedDigit()
                .foregroundStyle(NexusColor.Text.disabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 6).fill(rowBackgroundColor))
        .contentShape(Rectangle())
    }

    static func iconName(for kind: ItemKind) -> String {
        switch kind {
        case .note: return "doc.text"
        case .task: return "checkmark.circle"
        case .meeting: return "person.2"
        case .project: return "folder"
        case .section: return "square.split.2x1"
        case .savedFilter: return "line.3.horizontal.decrease.circle"
        case .debug: return "ladybug"
        case .agentMemory: return "brain.head.profile"
        }
    }

    /// Accent audit (spec §3): every kind is achromatic — the kind is
    /// conveyed by the chip's icon + label, not by hue.
    static func chipTone(for kind: ItemKind) -> NexusChipTone {
        .neutral
    }
}

#Preview {
    VStack(spacing: 0) {
        ItemRow(item: TaskItem(title: "Short title"))
        ItemRow(item: TaskItem(title: "A medium-length title that demonstrates wrapping behavior"))
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
