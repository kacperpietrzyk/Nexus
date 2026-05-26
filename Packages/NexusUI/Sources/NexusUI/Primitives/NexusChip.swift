import SwiftUI

public enum NexusChipTone: CaseIterable, Equatable, Sendable {
    case neutral
    case accent
    case rose
    case positive
    case negative
    case warning
}

/// Small, non-interactive label used for metadata and compact status chips.
public struct NexusChip: View {

    public let label: String
    public let systemImage: String?
    public let tone: NexusChipTone
    public let onRemove: (() -> Void)?

    public init(
        _ label: String,
        systemImage: String? = nil,
        tone: NexusChipTone = .neutral,
        onRemove: (() -> Void)? = nil
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.onRemove = onRemove
    }

    public var body: some View {
        if let onRemove {
            Button(role: .destructive, action: onRemove) {
                chipBody(includeRemoveIcon: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(label)"))
            .accessibilityHint(Text("Removes this chip."))
        } else {
            chipBody(includeRemoveIcon: false)
        }
    }

    private func chipBody(includeRemoveIcon: Bool) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .medium))
            }
            Text(label)
                .font(NexusType.caption)
            if includeRemoveIcon {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.65)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .foregroundStyle(textColor)
        .background(backgroundColor, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    internal var textColor: Color {
        switch tone {
        case .neutral: return NexusColor.Text.tertiary
        // Accent audit (spec §3): the strongest neutral chip — ink emphasis,
        // no hue. `.accent` survives as an enum case (call-sites + MP-6) but
        // renders achromatically here.
        case .accent: return NexusColor.Text.primary
        // .rose ≡ .negative post-MP-6.3 (both Text.primary); cases preserved —
        // §11 public-API byte-freeze, do not dedup.
        case .rose: return NexusColor.Text.primary
        case .positive: return NexusColor.Text.secondary
        case .negative: return NexusColor.Text.primary
        case .warning: return NexusColor.Text.secondary
        }
    }

    internal var backgroundColor: Color {
        switch tone {
        case .neutral: return Color.white.opacity(0.055)
        case .accent: return Color.white.opacity(0.10)
        // .rose ≡ .negative post-MP-6.3 (both Text.primary); cases preserved —
        // §11 public-API byte-freeze, do not dedup.
        case .rose: return NexusColor.Text.primary.opacity(0.12)
        case .positive: return NexusColor.Text.secondary.opacity(0.14)
        case .negative: return NexusColor.Text.primary.opacity(0.14)
        case .warning: return NexusColor.Text.secondary.opacity(0.14)
        }
    }

    internal var borderColor: Color {
        switch tone {
        case .neutral: return NexusColor.Line.hairline
        case .accent: return Color.white.opacity(0.16)
        // .rose ≡ .negative post-MP-6.3 (both Text.primary); cases preserved —
        // §11 public-API byte-freeze, do not dedup.
        case .rose: return NexusColor.Text.primary.opacity(0.35)
        case .positive: return NexusColor.Text.secondary.opacity(0.40)
        case .negative: return NexusColor.Text.primary.opacity(0.40)
        case .warning: return NexusColor.Text.secondary.opacity(0.40)
        }
    }
}

#Preview {
    HStack(spacing: 10) {
        NexusChip("backend")
        NexusChip("priority", systemImage: "exclamationmark", tone: .accent)
        NexusChip("late", systemImage: "exclamationmark.triangle.fill", tone: .rose)
        NexusChip("draft", systemImage: "pencil")
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
