import SwiftUI

/// Status / tag pill per `docs/03_COMPONENTS.md` §Pills / Tags.
///
/// 20 pt capsule with a caption label tinted by the given accent color.
/// `filled` deepens the fill and switches the label to primary ink for
/// stronger emphasis (e.g. active status vs. passive tag).
public struct LiquidPill: View {

    public let text: String
    public let color: Color
    public let filled: Bool

    public init(_ text: String, color: Color, filled: Bool = false) {
        self.text = text
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        Text(text)
            .font(DS.FontToken.caption)
            .foregroundStyle(filled ? DS.ColorToken.textPrimary : color)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(height: 20)
            .background {
                Capsule(style: .continuous)
                    // Tint formula ported from the starter
                    // (liquid_productivity_design_system/swiftui/LiquidGlassComponents.swift):
                    // 28% accent fill when filled, 14% when passive — visual calibration,
                    // no DS alpha tokens exist for accent tinting.
                    .fill(color.opacity(filled ? 0.28 : 0.14))
            }
            .overlay {
                Capsule(style: .continuous)
                    // 22% accent border, ported from the starter alongside the fill alphas.
                    .stroke(color.opacity(0.22), lineWidth: 1)
            }
    }
}
