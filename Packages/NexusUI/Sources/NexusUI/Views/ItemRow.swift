import NexusCore
import SwiftUI

/// Generic Linkable row — title + kind chip + relative timestamp.
/// Used by lists, search results, backlinks panel, command palette results.
public struct ItemRow: View {
    public let title: String
    public let kind: ItemKind
    public let updatedAt: Date
    public let maxTitleLength: Int
    public let isSelected: Bool

    public init(item: any Linkable, maxTitleLength: Int = 80, isSelected: Bool = false) {
        self.title = item.title
        self.kind = item.kind
        self.updatedAt = item.updatedAt
        self.maxTitleLength = maxTitleLength
        self.isSelected = isSelected
    }

    public var displayTitle: String {
        guard title.count > maxTitleLength else { return title }
        let trimmed = title.prefix(maxTitleLength)
        return trimmed + "…"
    }

    /// Flat Linear row resting background. The neutral resting state is
    /// `.clear` — content rows carry no per-row fill (separation is spacing).
    /// The active/selected state lifts to `Background.controlHover` (Charcoal
    /// Grey, surface 3), a flat opaque layer — never glass, never glow.
    internal var rowBackgroundColor: Color {
        isSelected ? NexusColor.Background.controlHover : .clear
    }

    public var body: some View {
        // Flat Linear treatment, status-glyph-free (ItemRow is generic over
        // all ItemKinds and has no status concept). Selection is signalled by
        // a subtle lime leading marker — lime's single reserved appearance on
        // this row — plus the Charcoal Grey row fill.
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: NexusRadius.tag, style: .continuous)
                .fill(isSelected ? NexusColor.Accent.lime : Color.clear)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
            NexusChip(kind.displayName, systemImage: Self.iconName(for: kind), tone: Self.chipTone(for: kind))
            Text(displayTitle)
                .nexusType(.bodySmall)
                .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(updatedAt, style: .relative)
                .nexusType(.caption)
                .monospacedDigit()
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: NexusRadius.r1).fill(rowBackgroundColor))
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
        case .scheduledBlock: return "calendar.badge.clock"
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
        ItemRow(item: TaskItem(title: "Selected row with the lime leading marker"), isSelected: true)
        ItemRow(item: TaskItem(title: "A medium-length title that demonstrates wrapping behavior"))
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
