import Testing

@testable import NexusUI

@Test func radius_scaleMatchesCossTokens() {
    #expect(NexusRadius.r1 == 6)
    #expect(NexusRadius.r2 == 8)
    #expect(NexusRadius.r3 == 12)
    #expect(NexusRadius.r4 == 16)
    #expect(NexusRadius.r5 == 20)
    #expect(NexusRadius.pill == 999)
}
