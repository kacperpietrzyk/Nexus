import Foundation
import Testing

@testable import NexusAI

@Suite(
    "KeychainSecretStore",
    .disabled(
        if: ProcessInfo.processInfo.environment["CI"] != nil,
        "Keychain Services unavailable on CI runners"
    )
)
struct KeychainSecretStoreTests {

    private func freshStore() -> KeychainSecretStore {
        // Each test uses a unique service name so they don't share keychain entries.
        // `useDataProtectionKeychain: false` because the SwiftPM test bundle is
        // unsigned/unentitled and would otherwise hit `errSecMissingEntitlement`.
        KeychainSecretStore(
            service: "test.nexus.ai.\(UUID().uuidString)",
            useDataProtectionKeychain: false
        )
    }

    @Test("retrieving missing secret returns nil")
    func missing() async {
        let store = freshStore()
        let result = await store.secret(for: .whisperKit)
        #expect(result == nil)
    }

    @Test("setSecret then secret returns stored value")
    func writeRead() async {
        let store = freshStore()
        await store.setSecret("secret-test-1234", for: .whisperKit)
        let read = await store.secret(for: .whisperKit)
        #expect(read == "secret-test-1234")
    }

    @Test("setSecret overwrites existing value")
    func overwrite() async {
        let store = freshStore()
        await store.setSecret("secret-old", for: .whisperKit)
        await store.setSecret("secret-new", for: .whisperKit)
        let read = await store.secret(for: .whisperKit)
        #expect(read == "secret-new")
    }

    @Test("setSecret(nil) deletes the entry")
    func deleteViaNil() async {
        let store = freshStore()
        await store.setSecret("secret-test", for: .whisperKit)
        await store.setSecret(nil, for: .whisperKit)
        let read = await store.secret(for: .whisperKit)
        #expect(read == nil)
    }

    @Test("each provider has independent storage")
    func providerIsolation() async {
        let store = freshStore()
        await store.setSecret("provider-secret", for: .whisperKit)
        let apple = await store.secret(for: .appleIntelligence)
        #expect(apple == nil)
        let whisper = await store.secret(for: .whisperKit)
        #expect(whisper == "provider-secret")
    }
}
