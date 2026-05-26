import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Suite("NexusWallpaper LabBackground")
struct NexusWallpaperTests {

    // MARK: Frozen public API

    @Test("Initializes via frozen public init and is a View")
    func initializes() {
        let wallpaper = NexusWallpaper()
        #expect(type(of: wallpaper).self == NexusWallpaper.self)
        // Compile-time guard: NexusWallpaper must remain a View.
        func requireView<V: View>(_ value: V) { _ = value }
        requireView(wallpaper)
    }

    // MARK: LabBackground base linear gradient

    @Test("Base linear gradient colors are the achromatic LabBackground stops")
    func baseLinearGradientColorsMatchLabBackground() {
        // Audit #14: the former cool-biased stops (panel 0x0D0E11 / base
        // 0x090A0C — B > R,G) are now true neutral grays panel 0x0E0E0E /
        // base 0x0A0A0A, genuinely r == g == b (Rec.601 luma of the old).
        assertColor(
            NexusWallpaper.linearTopColor,
            r: Double(0x0E) / 255, g: Double(0x0E) / 255, b: Double(0x0E) / 255, a: 1.0
        )
        assertColor(
            NexusWallpaper.linearBottomColor,
            r: Double(0x0A) / 255, g: Double(0x0A) / 255, b: Double(0x0A) / 255, a: 1.0
        )
    }

    @Test("Base linear gradient colors equal NexusColor Background panel/base")
    func baseLinearGradientMatchesBackgroundTokens() {
        #expect(
            NexusWallpaper.linearTopColor.resolvedRGBA == NexusColor.Background.panel.resolvedRGBA
        )
        #expect(
            NexusWallpaper.linearBottomColor.resolvedRGBA == NexusColor.Background.base.resolvedRGBA
        )
    }

    @Test("Base linear gradient direction matches LabBackground")
    func baseLinearGradientDirectionMatchesLabBackground() {
        #expect(NexusWallpaper.linearStartPoint == UnitPoint.top)
        #expect(NexusWallpaper.linearEndPoint == UnitPoint(x: 0.5, y: 0.9))
    }

    // MARK: LabBackground radial glows

    @Test("Three white radial glows match LabBackground")
    func radialGlowsMatchLabBackground() {
        #expect(NexusWallpaper.glows.count == 3)

        #expect(NexusWallpaper.glows[0].whiteOpacity == 0.07)
        #expect(NexusWallpaper.glows[0].center == UnitPoint(x: 0.34, y: 0.26))
        #expect(NexusWallpaper.glows[0].endRadius == 460)

        #expect(NexusWallpaper.glows[1].whiteOpacity == 0.055)
        #expect(NexusWallpaper.glows[1].center == UnitPoint(x: 0.86, y: 0.42))
        #expect(NexusWallpaper.glows[1].endRadius == 420)

        #expect(NexusWallpaper.glows[2].whiteOpacity == 0.035)
        #expect(NexusWallpaper.glows[2].center == UnitPoint(x: 0.5, y: 1.0))
        #expect(NexusWallpaper.glows[2].endRadius == 420)
    }

    @Test("All radial glows share a zero start radius")
    func radialGlowsShareZeroStartRadius() {
        #expect(NexusWallpaper.glowStartRadius == 0)
    }

    @Test("Glow tint resolves to white at the given opacity")
    func glowTintResolvesToWhite() {
        for glow in NexusWallpaper.glows {
            assertColor(
                Color.white.opacity(glow.whiteOpacity),
                r: 1.0, g: 1.0, b: 1.0, a: glow.whiteOpacity
            )
        }
    }

    // MARK: Reduce-Transparency fallback

    @Test("Reduce Transparency fallback color is base")
    func reduceTransparencyFallbackColorIsBase() {
        #expect(NexusWallpaper.baseColor.resolvedRGBA == NexusColor.Background.base.resolvedRGBA)
    }

    // MARK: Helpers

    private func assertColor(
        _ color: Color,
        r: Double,
        g: Double,
        b: Double,
        a: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let resolved = color.resolvedRGBA
        #expect(abs(resolved.r - r) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(resolved.g - g) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(resolved.b - b) < 0.0001, sourceLocation: sourceLocation)
        #expect(abs(resolved.a - a) < 0.0001, sourceLocation: sourceLocation)
    }
}
