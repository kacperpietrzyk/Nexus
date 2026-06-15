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

    // Glow intensities. macOS rides behind-window vibrancy, so a whisper of
    // colour is enough. iOS/iPadOS paint over a flat opaque base (no vibrancy to
    // carry the light), so the same opacities vanish — they are bumped here so the
    // aurora reads as brand, while staying restrained (never a loud gradient).
    #if os(macOS)
    private static let glowWhite = 0.010
    private static let glowAccent = 0.014
    private static let glowBlue = 0.008
    private static let grainOpacity = 0.018
    #else
    // iOS/iPadOS paint over a flat opaque base (no behind-window vibrancy), so
    // the aurora is an authored, premium composition (`iosAuroraLayers`) rather
    // than the macOS whisper-glaze — enough luminance up top that the light glass
    // cards read airy, with a vignette for focus.
    private static let grainOpacity = 0.024
    #endif

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

            RadialGradient(
                colors: [Color.white.opacity(Self.glowWhite), .clear],
                center: UnitPoint(x: 0.78, y: 0.22),
                startRadius: 0,
                endRadius: 460 * glowScale
            )

            RadialGradient(
                colors: [DS.ColorToken.accentPrimary.opacity(Self.glowAccent), .clear],
                center: UnitPoint(x: 0.52, y: 0.46),
                startRadius: 0,
                endRadius: 900 * glowScale
            )

            LinearGradient(
                colors: [DS.ColorToken.accentBlue.opacity(Self.glowBlue), .clear],
                startPoint: .top,
                endPoint: .center
            )
            #else
            iosAuroraLayers(glowScale: glowScale)
            #endif

            // Film grain so the large soft gradients don't band; tiled asset
            // from Resources/Wallpaper.
            Image("Wallpaper-Grain", bundle: .module)
                .resizable(resizingMode: .tile)
                .opacity(Self.grainOpacity)
                .blendMode(.plusLighter)
                .accessibilityHidden(true)
        }
    }

    #if !os(macOS)
    /// The authored iOS/iPadOS backdrop. A `MeshGradient` of warm, dark, organic
    /// tones — not a stack of cold radial glows — so it reads like the calm, warm
    /// premium feel of the macOS app (which gets its warmth free from the desktop
    /// photo behind window vibrancy). Mostly warm-charcoal/bronze with a faint
    /// plum + a single brand-indigo whisper, lifted gently up top so the light
    /// glass cards have luminance to sample, darker at the bottom for depth.
    @ViewBuilder
    private func iosAuroraLayers(glowScale: CGFloat) -> some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                // Deep, NEUTRAL premium-dark — very low saturation, calm. Warmth
                // is only a faint lift up top (where the first cards sample light),
                // never an amber wash; brand violet lives in UI accents, not here.
                Color(red: 0.110, green: 0.108, blue: 0.115),  // neutral
                Color(red: 0.140, green: 0.135, blue: 0.132),  // warm-neutral lift (focal)
                Color(red: 0.112, green: 0.110, blue: 0.122),  // faint cool
                Color(red: 0.085, green: 0.084, blue: 0.088),  // neutral charcoal
                Color(red: 0.108, green: 0.105, blue: 0.106),  // mid lift
                Color(red: 0.088, green: 0.087, blue: 0.096),  // dim neutral
                Color(red: 0.056, green: 0.056, blue: 0.059),  // deep neutral black
                Color(red: 0.060, green: 0.059, blue: 0.060),
                Color(red: 0.058, green: 0.057, blue: 0.066),
            ]
        )

        // A single, restrained depth glow up top — keeps the neutral field from
        // reading flat and gives the first cards a touch more luminance to sit on,
        // without a colour wash. Faint brand violet, very low opacity.
        RadialGradient(
            colors: [DS.ColorToken.accentPrimary.opacity(0.05), .clear],
            center: UnitPoint(x: 0.5, y: 0.0),
            startRadius: 0,
            endRadius: 680 * glowScale
        )
        .blendMode(.screen)

        // Edge vignette for depth + focus on the content.
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.34)],
            center: .center,
            startRadius: 160 * glowScale,
            endRadius: 940 * glowScale
        )
        .blendMode(.multiply)
    }
    #endif
}
