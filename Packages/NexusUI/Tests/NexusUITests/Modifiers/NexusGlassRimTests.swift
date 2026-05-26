import SwiftUI
import Testing

@testable import NexusUI

@MainActor
struct NexusGlassRimTests {

    @Test func rimRefractionTokenMatchesCanvas() {
        let expected = Color.white.opacity(0.07)
        #expect(NexusGlassRimSpec.refractionColor.resolvedRGBA == expected.resolvedRGBA)
    }

    @Test func rimFadeMatchesSpecTop() {
        #expect(NexusGlassRimSpec.topOpacity == 0.07)
        #expect(NexusGlassRimSpec.fadeEndLocation == 0.4)
    }

    @Test func modifierConstructs() {
        let modifier = NexusGlassRim(shape: RoundedRectangle(cornerRadius: NexusRadius.r3))
        let _: RoundedRectangle = modifier.shape
    }

    @Test func publicAPIAcceptsRoundedRectangleAndCapsule() {
        _ = Color.clear.nexusGlassRim(cornerRadius: 14)
        _ = Color.clear.nexusGlassRim(in: Capsule(style: .continuous))
    }
}
