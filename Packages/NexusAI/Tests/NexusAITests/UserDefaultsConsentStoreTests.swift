import Foundation
import Testing

@testable import NexusAI

@Suite("UserDefaultsConsentStore")
struct UserDefaultsConsentStoreTests {

    private func freshDefaults() -> UserDefaults {
        // Use ephemeral suite per test to avoid cross-test bleed.
        let suite = "test.consent.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("on-device providers always have consent (regardless of UserDefaults)")
    func onDeviceImplicitGrant() async {
        let store = UserDefaultsConsentStore(defaults: freshDefaults())
        #expect(await store.hasConsent(for: .appleIntelligence) == true)
        #expect(await store.hasConsent(for: .whisperKit) == true)
    }

    @Test("setConsent(false) does not revoke local provider")
    func localConsentCannotBeRevoked() async {
        let store = UserDefaultsConsentStore(defaults: freshDefaults())
        await store.setConsent(false, for: .appleIntelligence)
        #expect(await store.hasConsent(for: .appleIntelligence) == true)
    }

    @Test("migration prunes legacy Claude consent keys once")
    func migrationPrunesLegacyClaudeConsentKeys() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: UserDefaultsConsentStore.Keys.legacyShellConsent)
        defaults.set(true, forKey: UserDefaultsConsentStore.Keys.legacyClaudeConsent)

        _ = UserDefaultsConsentStore(defaults: defaults)

        #expect(defaults.object(forKey: UserDefaultsConsentStore.Keys.legacyShellConsent) == nil)
        #expect(defaults.object(forKey: UserDefaultsConsentStore.Keys.legacyClaudeConsent) == nil)
        #expect(defaults.bool(forKey: UserDefaultsConsentStore.Keys.claudePrunedMigrationApplied) == true)
    }

    @Test("migration prunes legacy OpenAI and BYOK consent keys")
    func migrationPrunesLegacyCloudCatchupConsentKeys() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "ai.consent.openai")
        defaults.set(true, forKey: "ai.consent.byok")
        defaults.set(true, forKey: "ai.consent.appleIntelligence")
        defaults.set(false, forKey: "ai.consent.migration.v2-pruneCloudCatchupStubs")

        _ = UserDefaultsConsentStore(defaults: defaults)

        #expect(defaults.object(forKey: "ai.consent.openai") == nil)
        #expect(defaults.object(forKey: "ai.consent.byok") == nil)
        #expect(defaults.bool(forKey: "ai.consent.appleIntelligence") == true)
        #expect(defaults.bool(forKey: "ai.consent.migration.v2-pruneCloudCatchupStubs") == true)
    }

    @Test("migration is skipped after Claude consent pruning marker is set")
    func migrationSkipsWhenAlreadyApplied() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: UserDefaultsConsentStore.Keys.claudePrunedMigrationApplied)
        defaults.set(true, forKey: UserDefaultsConsentStore.Keys.legacyShellConsent)
        defaults.set(true, forKey: UserDefaultsConsentStore.Keys.legacyClaudeConsent)

        _ = UserDefaultsConsentStore(defaults: defaults)

        #expect(defaults.bool(forKey: UserDefaultsConsentStore.Keys.legacyShellConsent) == true)
        #expect(defaults.bool(forKey: UserDefaultsConsentStore.Keys.legacyClaudeConsent) == true)
    }
}
