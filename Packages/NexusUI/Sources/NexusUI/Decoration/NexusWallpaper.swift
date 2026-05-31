import SwiftUI

/// Ambient wallpaper rendered behind every NexusUI surface.
///
/// Retargeted for Linear "Midnight Command Center": a single flat
/// `Background.base` (#08090A) fill — no blue glow, no large gradient. Linear
/// depth comes from layered `Background.*` surfaces and contained shadows, not
/// from an ambient wallpaper.
///
/// The legacy gradient / glow constants (`linearTopColor`, `glows`, …) are
/// retained as frozen-API guards asserted by `NexusWallpaperTests`; the body no
/// longer reads them.
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

    public var body: some View {
        // Linear is flat: a single Pitch Black (#08090A) ground. No gradient,
        // no radial glows — depth lives in the layered surfaces above.
        NexusWallpaper.baseColor
            .ignoresSafeArea()
    }
}
