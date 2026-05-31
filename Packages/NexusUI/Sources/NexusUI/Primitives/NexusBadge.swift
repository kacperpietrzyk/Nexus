import SwiftUI

public enum NexusBadgeTone: CaseIterable, Equatable, Sendable {
    case acc
    case pos
    case neg
    case warn
    case info
    case muted
}

public enum NexusBadgeSize: CaseIterable, Equatable, Sendable {
    case compact
    case control
}

/// Compact badge/control used for small status labels and low-density actions.
public struct NexusBadge: View {

    public let label: String
    public let systemImage: String?
    public let tone: NexusBadgeTone
    public let size: NexusBadgeSize
    public let action: (() -> Void)?

    public init(
        _ label: String,
        systemImage: String? = nil,
        tone: NexusBadgeTone = .muted,
        size: NexusBadgeSize = .compact,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
        self.size = action == nil ? size : .control
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(label)
                .font(textFont)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: minHeight)
        .foregroundStyle(textColor)
        .background(backgroundColor, in: badgeShape)
        .overlay(
            badgeShape
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    /// Linear badge — flat 4 px corner (`NexusRadius.badge`), not a pill.
    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NexusRadius.badge, style: .continuous)
    }

    internal var minHeight: CGFloat {
        switch size {
        case .compact: return 18
        case .control: return 32
        }
    }

    internal var horizontalPadding: CGFloat {
        switch size {
        case .compact: return 6
        case .control: return 16
        }
    }

    internal var verticalPadding: CGFloat {
        switch size {
        case .compact: return 0
        case .control: return 7
        }
    }

    private var textFont: Font {
        switch size {
        case .compact: return NexusType.eyebrow
        case .control: return NexusType.bodySmall
        }
    }

    // Linear badges are flat status labels, not primary actions, so every tone
    // renders the same neutral way: Charcoal Grey (`controlHover`) fill, Storm
    // Cloud (`Text.tertiary`) ink, hairline rim, 4 px corner. Lime is reserved
    // for primary actions / active selection and never appears on this chrome.
    // Cases are preserved (§11 public-API byte-freeze) — only the values change.
    internal var textColor: Color {
        switch tone {
        case .acc, .pos, .neg, .warn, .info, .muted:
            return NexusColor.Text.tertiary
        }
    }

    internal var backgroundColor: Color {
        switch tone {
        case .acc, .pos, .neg, .warn, .info, .muted:
            return NexusColor.Background.controlHover
        }
    }

    internal var borderColor: Color {
        switch tone {
        case .acc, .pos, .neg, .warn, .info, .muted:
            return NexusColor.Line.hairline
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        NexusBadge("Today")
        NexusBadge("Open", systemImage: "arrow.right", tone: .acc, size: .control) {}
        NexusBadge("Info", tone: .info)
        NexusBadge("Done", tone: .pos)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
