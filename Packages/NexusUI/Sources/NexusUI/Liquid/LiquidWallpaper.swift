import SwiftUI

#if os(macOS)
import AppKit

/// Behind-window vibrancy backdrop: blurs whatever is behind the WINDOW
/// (desktop wallpaper, other windows) so the app reads as real glass on the
/// desktop, not a painted-on dark sheet. `NSVisualEffectView` honors the
/// system Reduce-Transparency setting by flattening to an opaque material.
private struct WallpaperBlurBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // .hudWindow is the most translucent dark material — .underWindowBackground
        // measured ~1% desktop transmission (nearly opaque in dark mode).
        view.material = .hudWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

/// The Liquid wallpaper layer: a dark "dusk landscape" ground that sits UNDER
/// the glass panels. Shared by the main app shell and the Settings window so
/// every Liquid window paints the same ground. Pure decoration — no layout,
/// no business logic.
///
/// The reference boards (`liquid_productivity_design_system/references/`) put
/// a blurred photographic dusk wallpaper behind the glass. Sampled from
/// `01_today_dashboard.png`, its character is asymmetric, not a smooth
/// aurora: a bright, desaturated blue-gray hotspot just past the upper-right
/// edge (≈ rgb 81/98/119 at the margin), a moderate cool glow on the upper
/// left, warm ember patches along the bottom and lower-left (≈ rgb 55/38/30),
/// and a uniformly dark navy sky at the top. Glows below are authored at
/// final, post-scrim intensity (no scrim layer), and there is deliberately no
/// vignette — the brightest wallpaper lives AT the edges, where the panel
/// margins reveal it.
public struct LiquidWallpaper: View {

    public init() {}

    /// The frame the glow radii below were calibrated against (the main
    /// window's reference capture). Radii scale with the actual view so a
    /// small window (Settings, 900×552) gets the same light *composition*
    /// instead of sitting inside the main window's glow at full intensity.
    private static let designSize = CGSize(width: 1448, height: 974)

    public var body: some View {
        GeometryReader { proxy in
            let glowScale = max(
                proxy.size.width / Self.designSize.width,
                proxy.size.height / Self.designSize.height
            )
            wallpaperLayers(glowScale: glowScale)
        }
        .ignoresSafeArea()
    }

    private func wallpaperLayers(glowScale: CGFloat) -> some View {
        ZStack {
            #if os(macOS)
            // Behind-window blur stays as a living hint of the desktop, but
            // the glaze is thick enough that the wallpaper's own light — not
            // the user's desktop — sets the frame's luminance. The reference
            // boards are lit by their bundled dusk photo; a 0.4 glaze made
            // the whole app read flat black on a dark desktop.
            WallpaperBlurBackdrop()
            DS.ColorToken.backgroundApp.opacity(0.78)
            #else
            DS.ColorToken.backgroundApp
            #endif

            // Mid-frame violet haze: a quiet wash so the glass picks up the
            // boards' violet-navy cast through its ~28% transmission. The
            // panel luminance itself comes from the glass tints (JSON
            // alphas); margins between panels must stay dark navy
            // (reference margins measure ~rgb(15,19,27)).
            RadialGradient(
                colors: [DS.ColorToken.accentPrimary.opacity(0.16), .clear],
                center: UnitPoint(x: 0.52, y: 0.46),
                startRadius: 0,
                endRadius: 900 * glowScale
            )

            // Faint cool sky wash so the top margin reads navy, not black.
            LinearGradient(
                colors: [DS.ColorToken.accentBlue.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: .center
            )

            skyGlows(glowScale: glowScale)
            groundGlows(glowScale: glowScale)

            // Film grain so the large soft gradients don't band; tiled asset
            // from Resources/Wallpaper.
            Image("Wallpaper-Grain", bundle: .module)
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
        }
    }

    /// The cool upper half: moonlit hotspot off the upper-right edge, quiet
    /// upper-left glow, violet brand bloom in the mid-left air.
    private func skyGlows(glowScale: CGFloat) -> some View {
        ZStack {
            // THE hotspot: bright moonlit cloud just past the upper-right
            // edge — the strongest light in the frame. A desaturated white
            // core inside a blue bloom (white + blue sum to the reference's
            // blue-gray, not a saturated blue); tight radii so the light
            // falls off by mid-frame the way the photo does.
            RadialGradient(
                colors: [DS.ColorToken.accentBlue.opacity(0.55), .clear],
                center: UnitPoint(x: 1.10, y: 0.30),
                startRadius: 0,
                endRadius: 320 * glowScale
            )
            RadialGradient(
                colors: [Color.white.opacity(0.68), .clear],
                center: UnitPoint(x: 1.08, y: 0.30),
                startRadius: 0,
                endRadius: 280 * glowScale
            )

            // Quiet desaturated glow on the upper-left edge.
            RadialGradient(
                colors: [Color.white.opacity(0.08), .clear],
                center: UnitPoint(x: -0.06, y: 0.16),
                startRadius: 0,
                endRadius: 480 * glowScale
            )
            RadialGradient(
                colors: [DS.ColorToken.accentBlue.opacity(0.03), .clear],
                center: UnitPoint(x: -0.06, y: 0.16),
                startRadius: 0,
                endRadius: 520 * glowScale
            )

            // Violet brand bloom, mid-left air — pulled off the edge so the
            // lower-left margin stays warm, not lavender.
            RadialGradient(
                colors: [DS.ColorToken.accentPrimary.opacity(0.15), .clear],
                center: UnitPoint(x: 0.16, y: 0.44),
                startRadius: 0,
                endRadius: 640 * glowScale
            )
        }
    }

    /// The warm lower half: cyan mist under the center, sunset embers along
    /// the bottom, and the horizon band.
    private func groundGlows(glowScale: CGFloat) -> some View {
        ZStack {
            // Cyan haze under the center, light caught in mist.
            RadialGradient(
                colors: [DS.ColorToken.accentCyan.opacity(0.14), .clear],
                center: UnitPoint(x: 0.55, y: 0.74),
                startRadius: 0,
                endRadius: 560 * glowScale
            )

            // Warm ember patches: lower-left edge, bottom-center-left, and
            // bottom-right corner — the sunset side of the frame.
            RadialGradient(
                colors: [DS.ColorToken.accentAmber.opacity(0.12), .clear],
                center: UnitPoint(x: -0.04, y: 0.82),
                startRadius: 0,
                endRadius: 360 * glowScale
            )
            RadialGradient(
                colors: [DS.ColorToken.accentOrange.opacity(0.20), .clear],
                center: UnitPoint(x: 0.30, y: 1.08),
                startRadius: 0,
                endRadius: 420 * glowScale
            )
            RadialGradient(
                colors: [DS.ColorToken.accentAmber.opacity(0.16), .clear],
                center: UnitPoint(x: 0.94, y: 1.08),
                startRadius: 0,
                endRadius: 340 * glowScale
            )

            // Horizon band: a faint brightening just above the bottom edge so
            // the ground reads as landscape, not a void.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.66),
                    .init(color: DS.ColorToken.accentBlue.opacity(0.04), location: 0.84),
                    .init(color: DS.ColorToken.accentAmber.opacity(0.06), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
