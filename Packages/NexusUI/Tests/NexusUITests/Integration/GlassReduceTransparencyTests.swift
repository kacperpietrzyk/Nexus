import SwiftUI
import Testing

@testable import NexusUI

struct GlassReduceTransparencyTests {

    @Test func materialOpaqueFallback_regularIsCardSurface() {
        #expect(
            NexusGlassVariant.regular.opaqueFallback.resolvedRGBA
                == NexusColor.Background.raised.resolvedRGBA
        )
    }

    @Test func materialOpaqueFallback_subtleIsPanelSurface() {
        #expect(
            NexusGlassVariant.subtle.opaqueFallback.resolvedRGBA
                == NexusColor.Background.panel.resolvedRGBA
        )
    }

    @Test func materialOpaqueFallback_elevatedIsControlSurface() {
        #expect(
            NexusGlassVariant.elevated.opaqueFallback.resolvedRGBA
                == NexusColor.Background.control.resolvedRGBA
        )
    }

    @MainActor
    @Test func materialModifier_constructsForAllVariants() {
        // Smoke: ensure the Shape-generic modifier constructs for every variant.
        // `accessibilityReduceTransparency` is a read-only system environment value
        // (no public setter on `EnvironmentValues`), so the runtime branch can't be
        // forced from a unit test — the token-level `opaqueFallback` assertions
        // above ARE the integration assertion. Probing `.body` of `ModifiedContent`
        // is not supported by SwiftUI outside a host. Instead, verify the modifier
        // round-trips its variant + shape for every variant in `allCases`.
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        for variant in NexusGlassVariant.allCases {
            let modifier = NexusGlassMaterial(variant: variant, shape: shape)
            #expect(modifier.variant == variant)
        }
    }
}
