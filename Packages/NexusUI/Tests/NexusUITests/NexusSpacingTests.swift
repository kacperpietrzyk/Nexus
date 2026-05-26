import Testing

@testable import NexusUI

@Test func spacing_scaleMatchesCossTokens() {
    #expect(NexusSpacing.s1 == 4)
    #expect(NexusSpacing.s2 == 8)
    #expect(NexusSpacing.s3 == 12)
    #expect(NexusSpacing.s4 == 16)
    #expect(NexusSpacing.s5 == 20)
    #expect(NexusSpacing.s6 == 24)
    #expect(NexusSpacing.s7 == 32)
    #expect(NexusSpacing.s8 == 40)
    #expect(NexusSpacing.s9 == 56)
    #expect(NexusSpacing.s10 == 72)
}
