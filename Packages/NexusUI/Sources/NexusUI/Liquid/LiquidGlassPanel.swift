import SwiftUI

/// The liquid glass surface recipe — tinted material blur, hairline stroke,
/// top inner highlight, and a soft edge shadow.
///
/// Per `docs/09_SWIFTUI_IMPLEMENTATION_GUIDE.md` §Glass panel recipe: never rely
/// on `.ultraThinMaterial` alone; always tint it with a `DS.ColorToken.glass*`
/// fill so the panel stays dark and consistent over any wallpaper.
public struct LiquidGlassPanel: ViewModifier {

    /// Which glass tint the panel uses. Variants map 1:1 onto the
    /// `DS.ColorToken.glass*` tokens.
    public enum Variant: Sendable {
        case shell
        case sidebar
        case toolbar
        case card
        case strong
        case selected
    }

    public let variant: Variant
    public let cornerRadius: CGFloat
    public let isHovering: Bool

    public init(variant: Variant, cornerRadius: CGFloat, isHovering: Bool = false) {
        self.variant = variant
        self.cornerRadius = cornerRadius
        self.isHovering = isHovering
    }

    private var tint: Color {
        switch variant {
        case .shell: return DS.ColorToken.glassBase
        case .sidebar: return DS.ColorToken.glassSidebar
        case .toolbar: return DS.ColorToken.glassToolbar
        case .card: return isHovering ? DS.ColorToken.glassCardHover : DS.ColorToken.glassCard
        case .strong: return DS.ColorToken.glassStrong
        case .selected: return DS.ColorToken.glassSelected
        }
    }

    private var stroke: Color {
        isHovering ? DS.ColorToken.strokeStrong : DS.ColorToken.strokeDefault
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.ColorToken.strokeInnerHighlight, lineWidth: 0.5)
                    .blendMode(.screen)
                    .opacity(0.55)
            }
            .shadow(
                color: DS.ColorToken.shadowEdge,
                radius: variant == .card ? 18 : 28,
                x: 0,
                y: variant == .card ? 8 : 14
            )
    }
}

extension View {
    /// Applies the liquid glass surface recipe to any view.
    ///
    /// - Parameters:
    ///   - variant: the glass tint; defaults to `.card`.
    ///   - radius: corner radius; defaults to `DS.Radius.l` (16 pt — the card radius).
    ///   - isHovering: brightens the fill and stroke for hover feedback.
    public func liquidGlass(
        _ variant: LiquidGlassPanel.Variant = .card,
        radius: CGFloat = DS.Radius.l,
        isHovering: Bool = false
    ) -> some View {
        modifier(LiquidGlassPanel(variant: variant, cornerRadius: radius, isHovering: isHovering))
    }
}
