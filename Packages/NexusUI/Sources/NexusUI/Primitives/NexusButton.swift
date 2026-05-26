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

    // LabPill look (Lab/LabKit.swift `LabPill`): achromatic ink/read
    // foreground over the reconciled glass substrate, then `nexusPressable`.
    // `.ghost` drops the glass entirely (no fill, no rim) — foreground +
    // press only. `.default`/`.outline`/`.primary` share the glass; the
    // glass material's built-in 1pt rim is the only edge (LabPill carries no
    // separate stroke), so no per-variant border remains.
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
                .nexusGlass(.regular, cornerRadius: radius)
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
        case .sm, .md, .icon, .iconSm: return NexusRadius.r2
        case .lg: return NexusRadius.r3
        }
    }

    /// LabPill foreground: `.primary` is the strongest ink emphasis
    /// (`Text.primary`, == LabPill `strong`); every other variant uses the
    /// `read` ink (`Text.secondary`). No accent — emphasis is ink weight.
    internal var textColor: Color {
        variant == .primary ? NexusColor.Text.primary : NexusColor.Text.secondary
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
