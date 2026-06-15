import SwiftUI

/// The light "Today-style" glass card surface — the single source of truth for
/// the airy card look the design settled on (tuned against
/// `references/01_today_dashboard.png`).
///
/// Unlike `.liquidGlass(.card)` — which lays a dark navy glaze (≈0.34) over
/// `.contentBackground` and reads as a heavy slab — this uses `.ultraThinMaterial`
/// with minimal absorption, so the shell's aurora wallpaper reads through and the
/// card stays light. The shell owns the actual material sample; this only adds
/// rim light, local glare, and slight absorption so the screen does not become a
/// stack of nested blur panels.
///
/// `LiquidGlassCard` (macOS) and `TodayGlassCard` both route through this so the
/// recipe lives in exactly one place — no second copy to drift out of sync.
public struct LiquidLightCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let isHovering: Bool

    public init(cornerRadius: CGFloat = DS.Radius.m, isHovering: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isHovering = isHovering
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background { surfaceFill(shape) }
            .overlay { rimBorder(shape) }
            .overlay(alignment: .topLeading) { innerHighlight(shape) }
            .shadow(color: Color.black.opacity(0.070), radius: 8, x: 0, y: 4)
    }

    /// `.ultraThinMaterial` + light tint + soft glare + a faint corner chroma —
    /// the layers that keep the card light while the shell wallpaper reads through.
    private func surfaceFill(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(Color.white.opacity(isHovering ? 0.020 : 0.010))
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.fill(DS.ColorToken.glassCard.opacity(isHovering ? 0.18 : 0.090))
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovering ? 0.12 : 0.088), location: 0),
                                .init(color: Color.white.opacity(0.018), location: 0.20),
                                .init(color: .clear, location: 0.58),
                                .init(color: Color.black.opacity(0.030), location: 1),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            }
            .overlay {
                shape
                    .fill(
                        RadialGradient(
                            colors: [DS.ColorToken.accentBlue.opacity(isHovering ? 0.026 : 0.016), .clear],
                            center: UnitPoint(x: 0.08, y: 0.02),
                            startRadius: 12,
                            endRadius: 520
                        )
                    )
                    .blendMode(.screen)
            }
    }

    private func rimBorder(_ shape: RoundedRectangle) -> some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isHovering ? 0.30 : 0.22),
                        Color.white.opacity(0.046),
                        Color.black.opacity(0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private func innerHighlight(_ shape: RoundedRectangle) -> some View {
        shape
            .stroke(Color.white.opacity(isHovering ? 0.18 : 0.11), lineWidth: 0.5)
            .blur(radius: 0.45)
            .padding(0.5)
            .blendMode(.screen)
    }
}

extension View {
    /// Apply the light Today-style glass card surface (see `LiquidLightCardSurface`).
    ///
    /// macOS-only — the single entry point every card surface routes through, so
    /// the light recipe lives in one place. iOS falls back to the heavier
    /// `.liquidGlass(.card)` until the touch Liquid pass, so call sites in shared
    /// packages don't each need their own `#if`.
    public func liquidLightCard(cornerRadius: CGFloat = DS.Radius.m, isHovering: Bool = false) -> some View {
        #if os(macOS)
        modifier(LiquidLightCardSurface(cornerRadius: cornerRadius, isHovering: isHovering))
        #else
        liquidGlass(.card, radius: cornerRadius, isHovering: isHovering)
        #endif
    }
}
