import SwiftUI

/// A count that rolls digit-by-digit when its value changes (the change must
/// happen inside `withAnimation`). Static renders show the final value.
///
/// Linear "Midnight Command Center" skin: a gunmetal `controlHover` bubble with
/// `badge` radius and IBM Plex Mono digits. Neutral chrome — never lime.
public struct NexusCount: View {
    public let value: Int
    public var font: Font
    public var color: Color = NexusColor.Text.tertiary
    public init(value: Int, font: Font = NexusType.metaMono, color: Color = NexusColor.Text.tertiary) {
        self.value = value
        self.font = font
        self.color = color
    }
    public var body: some View {
        Text("\(value)")
            .font(font).monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                NexusColor.Background.controlHover,
                in: RoundedRectangle(cornerRadius: NexusRadius.badge, style: .continuous)
            )
    }
}
