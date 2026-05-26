import Foundation

/// Stores provider-scoped secrets for adapters that require them.
/// Phase 0f / Phase 1: real Keychain implementation in `NexusAI/Stores/KeychainSecretStore.swift`.
///
/// Secrets are never stored in SwiftData/CloudKit — Keychain only.
public protocol SecretStore: Sendable {
    func secret(for provider: ProviderID) async -> String?
    func setSecret(_ secret: String?, for provider: ProviderID) async
}
