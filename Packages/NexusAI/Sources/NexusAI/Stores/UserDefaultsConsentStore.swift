import Foundation

/// Production `ConsentStore` backed by `UserDefaults`. Local providers
/// (`.appleIntelligence`, `.whisperKit`) always have implicit grant via
/// `ProviderID.isOnDevice`; this matches the existing `InMemoryConsentStore`
/// contract.
///
/// `final class` + `@unchecked Sendable` rather than `actor` because `UserDefaults`
/// is itself thread-safe (Apple-documented), so an actor's serialization is
/// redundant. This matches `FakeAIProvider` (in `NexusAI/Testing/`) and
/// `FakeJobClock` (in `NexusCore/Scheduler/`) which wrap externally synchronized
/// state behind the same explicit `@unchecked Sendable` contract.
public final class UserDefaultsConsentStore: ConsentStore, @unchecked Sendable {

    public enum Keys {
        public static let legacyShellConsent = "ai.consent." + "claude" + "Shell"
        public static let legacyClaudeConsent = "ai.consent.claude"
        public static let claudePrunedMigrationApplied = "ai.consent.migration.1k-A.claude-pruned"
        public static let legacyOpenAIConsent = "ai.consent.openai"
        public static let legacyBYOKConsent = "ai.consent.byok"
        public static let cloudCatchupStubsPrunedMigrationApplied = "ai.consent.migration.v2-pruneCloudCatchupStubs"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        runMigrationsIfNeeded()
    }

    public func runMigrationsIfNeeded() {
        pruneClaudeConsentIfNeeded()
        pruneCloudCatchupStubConsentIfNeeded()
    }

    private func pruneClaudeConsentIfNeeded() {
        guard !defaults.bool(forKey: Keys.claudePrunedMigrationApplied) else { return }

        defaults.removeObject(forKey: Keys.legacyShellConsent)
        defaults.removeObject(forKey: Keys.legacyClaudeConsent)
        markMigrationApplied(Keys.claudePrunedMigrationApplied)
    }

    private func pruneCloudCatchupStubConsentIfNeeded() {
        guard !defaults.bool(forKey: Keys.cloudCatchupStubsPrunedMigrationApplied) else { return }

        defaults.removeObject(forKey: Keys.legacyOpenAIConsent)
        defaults.removeObject(forKey: Keys.legacyBYOKConsent)
        markMigrationApplied(Keys.cloudCatchupStubsPrunedMigrationApplied)
    }

    private func markMigrationApplied(_ key: String) {
        defaults.set(true, forKey: key)
    }

    public func hasConsent(for provider: ProviderID) -> Bool {
        switch provider {
        case .appleIntelligence, .whisperKit, .mlx:
            return true
        }
    }

    public func setConsent(_ granted: Bool, for provider: ProviderID) {
        switch provider {
        case .appleIntelligence, .whisperKit, .mlx:
            break  // on-device always granted; setter is a no-op.
        }
    }
}
