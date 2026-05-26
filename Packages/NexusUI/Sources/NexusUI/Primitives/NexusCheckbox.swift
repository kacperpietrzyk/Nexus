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
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var fillStyle: AnyShapeStyle {
        if isChecked {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [NexusColor.Text.primary, NexusColor.Text.primary],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }

        return AnyShapeStyle(Color.white.opacity(0.05))
    }

    internal var borderColor: Color {
        isChecked ? Color.white.opacity(0.16) : NexusColor.Line.strong
    }

    internal var shadowColor: Color {
        isChecked ? NexusColor.Text.primary.opacity(0.45) : .black.opacity(0.30)
    }

    internal var shadowRadius: CGFloat {
        isChecked ? 3 : 1
    }

    internal var shadowY: CGFloat {
        isChecked ? 0 : 1
    }

    internal static let side: CGFloat = 16
    internal static let cornerRadius: CGFloat = 5
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
