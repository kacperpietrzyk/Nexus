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
                    .fill(color.opacity(filled ? 0.40 : 0.16))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(filled ? 0.16 : 0.07), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Capsule(style: .continuous))
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(filled ? 0.55 : 0.24), lineWidth: 1)
            }
            .shadow(color: color.opacity(filled ? 0.22 : 0.08), radius: filled ? 8 : 4, x: 0, y: 0)
    }
}
