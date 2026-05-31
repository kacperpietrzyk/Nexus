import SwiftUI
import Testing

@testable import NexusUI

/// Asserts that NexusShadow token values match the Linear "Midnight Command Center" shadow set.
@Test func shadow_profilesMatchLinearTokens() {
    // s1 — small card drop (--shadow-sm: rgba(0,0,0,0.4) 0 2px 4px)
    #expect(NexusShadow.s1.radius == 2)
    #expect(NexusShadow.s1.x == 0)
    #expect(NexusShadow.s1.y == 2)

    // s2 — medium panel drop
    #expect(NexusShadow.s2.radius == 6)
    #expect(NexusShadow.s2.x == 0)
    #expect(NexusShadow.s2.y == 4)

    // pop — elevated overlay (--shadow-xl: rgba(8,9,10,0.6) 0 4px 32px)
    #expect(NexusShadow.pop.radius == 16)
    #expect(NexusShadow.pop.x == 0)
    #expect(NexusShadow.pop.y == 4)

    // glass — floating surface
    #expect(NexusShadow.glass.radius == 8)
    #expect(NexusShadow.glass.x == 0)
    #expect(NexusShadow.glass.y == 4)

    // accentGlow — contained, not a broad diffuse glow
    #expect(NexusShadow.accentGlow.radius == 4)
    #expect(NexusShadow.accentGlow.x == 0)
    #expect(NexusShadow.accentGlow.y == 2)
}
