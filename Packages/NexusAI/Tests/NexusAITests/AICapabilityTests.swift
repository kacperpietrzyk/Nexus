import Testing

@testable import NexusAI

@Test func aiCapability_rawValues_areStable() {
    #expect(AICapability.generate.rawValue == "generate")
    #expect(AICapability.transcribe.rawValue == "transcribe")
    #expect(AICapability.embed.rawValue == "embed")
    #expect(AICapability.longContext.rawValue == "longContext")
}

@Test func aiCapability_isHashable_andCanFormSet() {
    let s: Set<AICapability> = [.generate, .embed, .generate]
    #expect(s == [.generate, .embed])
}

@Test func aiCapability_allCases_haveStableOrder() {
    #expect(AICapability.allCases == [.generate, .transcribe, .embed, .longContext])
}
