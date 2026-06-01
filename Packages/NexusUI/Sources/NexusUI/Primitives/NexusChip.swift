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
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(textColor)
        .background(backgroundColor, in: chipShape)
        .overlay(
            chipShape
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    /// Linear tag/badge — flat 4 px corner (`NexusRadius.badge`), not a pill.
    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NexusRadius.badge, style: .continuous)
    }

    internal var textColor: Color {
        switch tone {
        // `.accent` is the single active/selected chip — Porcelain ink paired
        // with the lime rim below. Lime stays on the rim only (economy rule).
        case .accent: return NexusColor.Text.primary
        // Neutral chrome (tags, P2/P3, future-due) recedes to Storm Cloud ink so
        // the loud semantic tones below carry the hierarchy.
        case .neutral: return NexusColor.Text.tertiary
        // Restrained semantic ink — tinted text only; the fill/rim below stay
        // faint so no chip ever reads as a saturated block. `.warning` shares
        // the danger family (amber is forbidden — lime-adjacent).
        case .rose, .negative, .warning: return NexusColor.Status.danger
        case .positive: return NexusColor.Status.success
        }
    }

    internal var backgroundColor: Color {
        switch tone {
        // Active/selected reads via the lime rim, so keep a flat charcoal fill
        // a half-step up from the resting chip for a contained lift.
        case .accent: return NexusColor.Background.controlHover
        // Resting metadata chips: flat control fill (#1C1D1F). No translucency.
        case .neutral: return NexusColor.Background.control
        // Very faint tinted wash — restrained, never a saturated fill.
        case .rose, .negative: return NexusColor.Status.danger.opacity(0.10)
        // Amber is forbidden (lime-adjacent) — soft caution is the faintest red,
        // not amber. Lowest-intensity red in the danger family.
        case .warning: return NexusColor.Status.danger.opacity(0.06)
        case .positive: return NexusColor.Status.success.opacity(0.10)
        }
    }

    internal var borderColor: Color {
        switch tone {
        // The one place lime is allowed on this primitive: a subtle rim marking
        // the single active/selected state. Never on neutral chrome.
        case .accent: return NexusColor.Accent.lime.opacity(0.45)
        // Neutral hairline rim for every resting chip.
        case .neutral: return NexusColor.Line.hairline
        // Subtle tinted rim, paired with the faint wash above.
        case .rose, .negative: return NexusColor.Status.danger.opacity(0.30)
        case .warning: return NexusColor.Status.danger.opacity(0.22)
        case .positive: return NexusColor.Status.success.opacity(0.30)
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
