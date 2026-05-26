import SwiftUI

/// A count that rolls digit-by-digit when its value changes (the change must
/// happen inside `withAnimation`). Static renders show the final value.
public struct NexusCount: View {
    public let value: Int
    public var font: Font
    public var color: Color = NexusColor.Text.disabled
    public init(value: Int, font: Font, color: Color = NexusColor.Text.disabled) {
        self.value = value
        self.font = font
        self.color = color
    }
    public var body: some View {
        Text("\(value)")
            .font(font).monospacedDigit()
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}
