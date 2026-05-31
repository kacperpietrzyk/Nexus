import SwiftUI

public struct NexusCheckbox: View {
    @Binding public var isChecked: Bool
    public let accessibilityLabel: String

    public init(isChecked: Binding<Bool>, accessibilityLabel: String = "Toggle selection") {
        self._isChecked = isChecked
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Button(
            action: { isChecked.toggle() },
            label: {
                box
            }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isChecked ? "Checked" : "Unchecked")
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    @ViewBuilder private var box: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(fillStyle)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NexusColor.Accent.limeInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    // Unchecked: transparent square. Checked: flat neon-lime fill (the single
    // completed indicator — lime is reserved for exactly this active state).
    private var fillStyle: AnyShapeStyle {
        isChecked
            ? AnyShapeStyle(NexusColor.Accent.lime)
            : AnyShapeStyle(Color.clear)
    }

    // Unchecked: 1px Gunmetal rim. Checked: lime rim flush with the fill (no
    // contrasting chrome — Linear surfaces are flat, not glassy).
    internal var borderColor: Color {
        isChecked ? NexusColor.Accent.lime : NexusColor.Line.strong
    }

    internal static let side: CGFloat = 16
    internal static let cornerRadius: CGFloat = NexusRadius.badge
}

#Preview {
    struct PreviewContent: View {
        @State private var checked = true

        var body: some View {
            NexusCheckbox(isChecked: $checked, accessibilityLabel: "Done")
        }
    }

    return PreviewContent()
        .padding(40)
        .background(NexusColor.Background.base)
}
