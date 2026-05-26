import SwiftUI
import Testing

@testable import NexusUI

struct NexusGlassMaterialTests {

    @Test func variantsAreCaseIterable() {
        #expect(NexusGlassVariant.allCases.count == 3)
        #expect(NexusGlassVariant.allCases.contains(.subtle))
        #expect(NexusGlassVariant.allCases.contains(.regular))
        #expect(NexusGlassVariant.allCases.contains(.elevated))
    }

    @Test func variantTintMatchesV4GlassTokens() {
        #expect(NexusGlassVariant.subtle.tint.resolvedRGBA == NexusColor.Glass.surface1.resolvedRGBA)
        #expect(NexusGlassVariant.regular.tint.resolvedRGBA == NexusColor.Glass.surface2.resolvedRGBA)
        #expect(NexusGlassVariant.elevated.tint.resolvedRGBA == NexusColor.Glass.surface3.resolvedRGBA)
    }

    @Test func variantBorderColor() {
        #expect(
            NexusGlassVariant.subtle.borderColor.resolvedRGBA
                == NexusColor.Line.hairline.resolvedRGBA
        )
        #expect(
            NexusGlassVariant.regular.borderColor.resolvedRGBA
                == NexusColor.Line.regular.resolvedRGBA
        )
        #expect(
            NexusGlassVariant.elevated.borderColor.resolvedRGBA
                == NexusColor.Line.strong.resolvedRGBA
        )
    }

    @Test func reduceTransparencyFallbackTint() {
        // When Reduce Transparency is on, glass collapses to an opaque v4 surface.
        #expect(
            NexusGlassVariant.subtle.opaqueFallback.resolvedRGBA
                == NexusColor.Background.panel.resolvedRGBA
        )
        #expect(
            NexusGlassVariant.regular.opaqueFallback.resolvedRGBA
                == NexusColor.Background.raised.resolvedRGBA
        )
        #expect(
            NexusGlassVariant.elevated.opaqueFallback.resolvedRGBA
                == NexusColor.Background.control.resolvedRGBA
        )
    }

    @MainActor
    @Test func glassMaterialAcceptsCustomShape() {
        // Smoke test that the Shape-generic init compiles and round-trips the shape.
        let material = NexusGlassMaterial(variant: .subtle, shape: Capsule(style: .continuous))
        #expect(material.variant == .subtle)
    }

    @Test func specularTopAlphaMatchesCanvasSpecToken() {
        // Canvas `--spec-top` is white at 7% alpha. The earlier implementation
        // chained `.opacity(0.07).opacity(0.80)` which collapsed to ~0.056 and
        // degraded the specular rim. Verify the constant survives intact.
        let rgba = NexusGlassMaterial<RoundedRectangle>.specularTopAlpha.resolvedRGBA

        #expect(rgba.a > 0.06)
        #expect(rgba.a < 0.08)
    }

    // MARK: - Frozen-API guard (MP-0 LabKit migration)

    @MainActor
    @Test func frozenPublicEntryPointsStillCompile() {
        // The LabKit-look reconciliation freezes the public surface: every
        // public entry point must still compile with its pre-migration call
        // shape. This is the compile-time contract, not a behaviour check.
        _ = Color.clear.nexusGlass()
        _ = Color.clear.nexusGlass(.subtle)
        _ = Color.clear.nexusGlass(.regular, cornerRadius: 14)
        _ = Color.clear.nexusGlass(.elevated, in: Capsule(style: .continuous))

        let roundedInit = NexusGlassMaterial<RoundedRectangle>(variant: .regular, cornerRadius: 20)
        #expect(roundedInit.variant == .regular)

        let shapeInit = NexusGlassMaterial(variant: .subtle, shape: Capsule(style: .continuous))
        #expect(shapeInit.variant == .subtle)
    }

    // MARK: - LabGlass-look behaviour (MP-0 LabKit migration)

    @Test func rimGradientMatchesLabKitTokens() {
        // LabGlass rim is a top→bottom white gradient: 0.16 → 0.07. These
        // values are LabKit-exact and frozen. The modifier body builds its
        // rim from the SAME constants (single source of truth).
        let colors = NexusGlassMaterial<RoundedRectangle>.rimGradientColors
        #expect(colors.count == 2)
        #expect(colors[0].resolvedRGBA == Color.white.opacity(0.16).resolvedRGBA)
        #expect(colors[1].resolvedRGBA == Color.white.opacity(0.07).resolvedRGBA)
        #expect(NexusGlassMaterial<RoundedRectangle>.rimLineWidth == 1)
    }

    @Test func shadowMatchesLabKitElevationScale() {
        // LabGlass keys its shadow off an `elevated: Bool`. Production maps
        // `.elevated → true`, `.subtle`/`.regular → false`. Both value-sets
        // are LabKit-exact: opacity 0.55/0.35, radius 24/12, y 12/5.
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowOpacity(elevated: true) == 0.55)
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowOpacity(elevated: false) == 0.35)
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowRadius(elevated: true) == 24)
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowRadius(elevated: false) == 12)
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowY(elevated: true) == 12)
        #expect(NexusGlassMaterial<RoundedRectangle>.shadowY(elevated: false) == 5)
    }

    @Test func variantMapsToLabKitElevationFlag() {
        // The 3-variant axis collapses onto LabGlass's binary `elevated`.
        #expect(NexusGlassVariant.elevated.isElevatedSurface)
        #expect(!NexusGlassVariant.regular.isElevatedSurface)
        #expect(!NexusGlassVariant.subtle.isElevatedSurface)
    }
}
