import Foundation

/// Tracks user consent for each provider. Local providers always have implicit
/// consent because data never leaves the device.
///
/// Async because real implementations may persist to UserDefaults or CloudKit
/// private DB (Phase 0f settings).
public protocol ConsentStore: Sendable {
    func hasConsent(for provider: ProviderID) async -> Bool
    func setConsent(_ granted: Bool, for provider: ProviderID) async
}

extension ProviderID {
    /// On-device providers don't require consent — data never leaves the device.
    /// The router uses this to short-circuit consent checks.
    public var isOnDevice: Bool {
        switch self {
        case .appleIntelligence, .whisperKit, .mlx: return true
        }
    }
}
