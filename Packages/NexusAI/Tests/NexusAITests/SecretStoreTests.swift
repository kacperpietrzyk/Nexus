import Testing

@testable import NexusAI

@Test func inMemorySecretStore_default_hasNoSecret() async {
    let s = InMemorySecretStore()
    #expect(await s.secret(for: .whisperKit) == nil)
}

@Test func inMemorySecretStore_setSecret_isReadable() async {
    let s = InMemorySecretStore()
    await s.setSecret("secret-abc123", for: .whisperKit)
    #expect(await s.secret(for: .whisperKit) == "secret-abc123")
}

@Test func inMemorySecretStore_clearSecret_removesIt() async {
    let s = InMemorySecretStore()
    await s.setSecret("secret-abc", for: .whisperKit)
    await s.setSecret(nil, for: .whisperKit)
    #expect(await s.secret(for: .whisperKit) == nil)
}
