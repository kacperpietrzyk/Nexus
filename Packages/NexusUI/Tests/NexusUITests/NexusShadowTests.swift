import SwiftUI
import Testing

@testable import NexusUI

@Test func shadow_profilesMatchCossTokens() {
    #expect(NexusShadow.s1.radius == 2)
    #expect(NexusShadow.s1.x == 0)
    #expect(NexusShadow.s1.y == 1)

    #expect(NexusShadow.s2.radius == 28)
    #expect(NexusShadow.s2.x == 0)
    #expect(NexusShadow.s2.y == 8)

    #expect(NexusShadow.pop.radius == 48)
    #expect(NexusShadow.pop.x == 0)
    #expect(NexusShadow.pop.y == 16)

    #expect(NexusShadow.glass.radius == 32)
    #expect(NexusShadow.glass.x == 0)
    #expect(NexusShadow.glass.y == 12)

    #expect(NexusShadow.accentGlow.radius == 14)
    #expect(NexusShadow.accentGlow.x == 0)
    #expect(NexusShadow.accentGlow.y == 4)
    #expect(
        NexusShadow.accentGlow.color.resolvedRGBA
            == NexusColor.Text.primary.opacity(0.45).resolvedRGBA
    )
}
