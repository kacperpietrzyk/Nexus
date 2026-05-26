import Foundation

// MARK: - For testing only
//
// Public so feature-module test targets can inject this without redefining.
// Production composition root MUST use a `UserDefaults`/CloudKit-backed store
// (Phase 0f). Wrapping a `Dictionary` in `actor` keeps the value `Sendable`
// without `@unchecked`.

public actor InMemoryConsentStore: ConsentStore {
    private var grants: [ProviderID: Bool] = [:]

    public init() {}

    public func hasConsent(for provider: ProviderID) -> Bool {
        if provider.isOnDevice { return true }
        return grants[provider] ?? false
    }

    public func setConsent(_ granted: Bool, for provider: ProviderID) {
        grants[provider] = granted
    }
}
