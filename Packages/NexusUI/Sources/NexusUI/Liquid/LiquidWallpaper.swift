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
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

/// The Liquid backdrop layer. On macOS this samples the real content behind
/// the window through `NSVisualEffectView(.behindWindow)`; app-authored color
/// only adds a slight readability glaze and grain, never a fake desktop image.
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
            WallpaperBlurBackdrop()
            Color.black.opacity(0.085)
            #else
            DS.ColorToken.backgroundApp
            #endif

            RadialGradient(
                    colors: [Color.white.opacity(0.010), .clear],
                center: UnitPoint(x: 0.78, y: 0.22),
                startRadius: 0,
                endRadius: 460 * glowScale
            )

            RadialGradient(
                    colors: [DS.ColorToken.accentPrimary.opacity(0.014), .clear],
                center: UnitPoint(x: 0.52, y: 0.46),
                startRadius: 0,
                endRadius: 900 * glowScale
            )

            LinearGradient(
                    colors: [DS.ColorToken.accentBlue.opacity(0.008), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // Film grain so the large soft gradients don't band; tiled asset
            // from Resources/Wallpaper.
            Image("Wallpaper-Grain", bundle: .module)
                .resizable(resizingMode: .tile)
                .opacity(0.018)
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
        }
    }
}
