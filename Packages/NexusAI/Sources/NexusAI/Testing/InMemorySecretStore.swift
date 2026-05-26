import Foundation

// MARK: - For testing only
//
// Trivial dictionary-backed secret store for tests + previews.
// Production must use the Keychain implementation landing in Phase 0f.

public actor InMemorySecretStore: SecretStore {
    private var secrets: [ProviderID: String] = [:]

    public init() {}

    public func secret(for provider: ProviderID) -> String? {
        secrets[provider]
    }

    public func setSecret(_ secret: String?, for provider: ProviderID) {
        if let secret {
            secrets[provider] = secret
        } else {
            secrets.removeValue(forKey: provider)
        }
    }
}
