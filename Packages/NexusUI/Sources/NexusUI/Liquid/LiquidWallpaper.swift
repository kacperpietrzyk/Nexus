import SwiftUI

/// The Liquid wallpaper layer: a dark "dusk aurora" ground that sits UNDER the
/// glass panels. Shared by the main app shell and the Settings window so every
/// Liquid window paints the same ground. Both layers ignore the safe area;
/// pure decoration — no layout, no business logic.
///
/// The reference boards (`liquid_productivity_design_system/references/`) put a
/// blurred, photographic dusk wallpaper behind the glass: cool blue light from
/// the top, a violet bloom on the left, and a warm amber horizon low in the
/// frame. The glass recipe only reads as *glass* when that color exists for the
/// material to blur. The `wallpaperScrim` token is for photographic sources;
/// these procedural glows are authored at their final, post-scrim intensity
/// instead, so no scrim layer sits on top.
public struct LiquidWallpaper: View {

    public init() {}

    public var body: some View {
        ZStack {
            DS.ColorToken.backgroundApp

            // Cool sky light, top trailing — the dominant source.
            RadialGradient(
                colors: [DS.ColorToken.accentBlue.opacity(0.42), .clear],
                center: UnitPoint(x: 0.82, y: -0.08),
                startRadius: 0,
                endRadius: 860
            )

            // Violet bloom, mid leading — the brand accent in the air.
            RadialGradient(
                colors: [DS.ColorToken.accentPrimary.opacity(0.36), .clear],
                center: UnitPoint(x: 0.06, y: 0.38),
                startRadius: 0,
                endRadius: 780
            )

            // Cyan haze under the center, like light caught in mist.
            RadialGradient(
                colors: [DS.ColorToken.accentCyan.opacity(0.20), .clear],
                center: UnitPoint(x: 0.58, y: 0.72),
                startRadius: 0,
                endRadius: 640
            )

            // Warm horizon, low leading — the sunset edge of the frame.
            RadialGradient(
                colors: [DS.ColorToken.accentAmber.opacity(0.30), .clear],
                center: UnitPoint(x: 0.18, y: 1.10),
                startRadius: 0,
                endRadius: 620
            )

            // Horizon band: a faint brightening just above the bottom edge so
            // the ground reads as landscape, not a void.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.62),
                    .init(color: DS.ColorToken.accentBlue.opacity(0.12), location: 0.80),
                    .init(color: DS.ColorToken.accentAmber.opacity(0.14), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Vignette keeps the corners quiet so the glass panels stay the
            // brightest shapes in the frame.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.30)],
                center: .center,
                startRadius: 420,
                endRadius: 1200
            )

            // Film grain so the large soft gradients don't band; tiled asset
            // from Resources/Wallpaper.
            Image("Wallpaper-Grain", bundle: .module)
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
