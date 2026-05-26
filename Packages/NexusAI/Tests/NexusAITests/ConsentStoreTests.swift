import Testing

@testable import NexusAI

@Test func inMemoryConsentStore_default_allowsLocalProviders() async {
    let s = InMemoryConsentStore()
    #expect(await s.hasConsent(for: .appleIntelligence) == true)  // on-device — always allowed
    #expect(await s.hasConsent(for: .whisperKit) == true)
}

@Test func inMemoryConsentStore_setConsent_doesNotRevokeLocalProvider() async {
    let s = InMemoryConsentStore()
    await s.setConsent(false, for: .appleIntelligence)
    #expect(await s.hasConsent(for: .appleIntelligence) == true)
}
