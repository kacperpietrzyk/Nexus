import SwiftUI

public enum NexusButtonVariant: CaseIterable, Equatable, Sendable {
    case `default`
    case primary
    case outline
    case ghost
}

public enum NexusButtonSize: CaseIterable, Equatable, Sendable {
    case sm
    case md
    case lg
    case icon
    case iconSm
}

public struct NexusButton<Label: View>: View {
    public let variant: NexusButtonVariant
    public let size: NexusButtonSize
    public let action: () -> Void
    @ViewBuilder public let label: () -> Label

    public init(
        variant: NexusButtonVariant = .default,
        size: NexusButtonSize = .md,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            styledLabel
        }
        .buttonStyle(NexusPressableButtonStyle())
    }

    // Linear flat button: a contained surface (no glass, no glow) with a 1px
    // Line rim and a small `s1` drop. `.primary` is the only variant that
    // breaks neutrality — a solid Neon Lime fill with limeInk ink, the single
    // accent the component is allowed. `.default`/`.outline` are neutral flat
    // substrates over the Background ladder. `.ghost` drops the surface
    // entirely (transparent, no rim, no shadow) — foreground + press only.
    @ViewBuilder private var styledLabel: some View {
        let content =
            label()
            .font(textFont)
            .foregroundStyle(textColor)
            .padding(.horizontal, hPadding)
            .frame(width: fixedWidth, height: height)

        if variant == .ghost {
            content
        } else {
            content
                .background(fillColor, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: borderColor == .clear ? 0 : 1)
                }
                .nexusShadow(NexusShadow.s1)
        }
    }

    internal var height: CGFloat {
        switch size {
        case .sm, .iconSm: return 26
        case .md, .icon: return 30
        case .lg: return 36
        }
    }

    internal var hPadding: CGFloat {
        switch size {
        case .sm: return 10
        case .md: return 12
        case .lg: return 16
        case .icon, .iconSm: return 0
        }
    }

    internal var radius: CGFloat {
        switch size {
        case .sm, .md, .icon, .iconSm: return NexusRadius.r1
        case .lg: return NexusRadius.r3
        }
    }

    /// Linear foreground ink. `.primary` draws on a Neon Lime fill, so it uses
    /// `Accent.limeInk` (pitch black) for legible contrast; every neutral
    /// variant uses the secondary read ink. No accent appears on text.
    internal var textColor: Color {
        variant == .primary ? NexusColor.Accent.limeInk : NexusColor.Text.secondary
    }

    /// Flat surface fill. `.primary` is the single lime fill; `.default` rides
    /// the raised surface, `.outline` the recessed control fill. `.ghost` has
    /// no fill (it never reaches this property — the surface is omitted).
    internal var fillColor: Color {
        switch variant {
        case .primary: return NexusColor.Accent.lime
        case .default: return NexusColor.Background.raised
        case .outline: return NexusColor.Background.control
        case .ghost: return .clear
        }
    }

    /// 1px Line rim. The lime `.primary` fill carries its own edge, so it takes
    /// no border; neutral variants get a hairline (`.default`) or stronger
    /// (`.outline`) Line. `.ghost` has no rim.
    internal var borderColor: Color {
        switch variant {
        case .primary: return .clear
        case .default: return NexusColor.Line.hairline
        case .outline: return NexusColor.Line.strong
        case .ghost: return .clear
        }
    }

    internal var fixedWidth: CGFloat? {
        switch size {
        case .icon:
            return 30
        case .iconSm:
            return 26
        case .sm, .md, .lg:
            return nil
        }
    }

    internal var textFont: Font {
        switch size {
        case .sm, .iconSm:
            return NexusType.meta
        case .md, .icon:
            return NexusType.bodySmall
        case .lg:
            return NexusType.body
        }
    }

}

#Preview {
    VStack(spacing: 12) {
        NexusButton(
            variant: .primary, size: .lg, action: {},
            label: {
                Text("Continue")
            })
        NexusButton(
            variant: .outline, size: .md, action: {},
            label: {
                Text("Secondary")
            })
        NexusButton(
            variant: .ghost, size: .sm, action: {},
            label: {
                Text("Cancel")
            })
        NexusButton(
            variant: .default, size: .icon, action: {},
            label: {
                Image(systemName: "plus")
            })
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
