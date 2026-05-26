import SwiftUI

/// Ambient wallpaper rendered behind every NexusUI surface.
///
/// Composition (back-to-front), adopting the LabKit `LabBackground` stack:
///   1. Vertical linear gradient from `Background.panel` (top) to `Background.base`
///      (bottom-biased end point), both achromatic.
///   2. Three soft white radial glows (top-left, mid-right, bottom-center).
///
/// Reduce Transparency collapses to the opaque achromatic base color only.
public struct NexusWallpaper: View {

    /// One soft white radial glow in the LabBackground stack.
    struct Glow {
        /// Opacity of the white centre stop (fades to `.clear`).
        let whiteOpacity: Double
        /// Gradient centre, in unit-point coordinates.
        let center: UnitPoint
        /// Outer radius of the radial gradient in points.
        let endRadius: Double
    }

    /// Achromatic base color used by the Reduce-Transparency fallback.
    public static let baseColor = NexusColor.Background.base

    /// Top color of the base linear gradient (achromatic; == `Background.panel`).
    static let linearTopColor = NexusColor.Background.panel
    /// Bottom color of the base linear gradient (achromatic; == `Background.base`).
    static let linearBottomColor = NexusColor.Background.base
    /// Start point of the base linear gradient.
    static let linearStartPoint = UnitPoint.top
    /// End point of the base linear gradient (bottom-biased per LabBackground).
    static let linearEndPoint = UnitPoint(x: 0.5, y: 0.9)

    /// Shared start radius for every radial glow.
    static let glowStartRadius: Double = 0

    /// The three white radial glows, back-to-front, matching `LabBackground`.
    static let glows: [Glow] = [
        Glow(whiteOpacity: 0.07, center: UnitPoint(x: 0.34, y: 0.26), endRadius: 460),
        Glow(whiteOpacity: 0.055, center: UnitPoint(x: 0.86, y: 0.42), endRadius: 420),
        Glow(whiteOpacity: 0.035, center: UnitPoint(x: 0.5, y: 1.0), endRadius: 420),
    ]

    public init() {}

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public var body: some View {
        if reduceTransparency {
            NexusWallpaper.baseColor
                .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        NexusWallpaper.linearTopColor,
                        NexusWallpaper.linearBottomColor,
                    ],
                    startPoint: NexusWallpaper.linearStartPoint,
                    endPoint: NexusWallpaper.linearEndPoint
                )

                ForEach(Array(NexusWallpaper.glows.enumerated()), id: \.offset) { _, glow in
                    RadialGradient(
                        colors: [Color.white.opacity(glow.whiteOpacity), .clear],
                        center: glow.center,
                        startRadius: NexusWallpaper.glowStartRadius,
                        endRadius: glow.endRadius
                    )
                }
            }
            .ignoresSafeArea()
        }
    }
}
