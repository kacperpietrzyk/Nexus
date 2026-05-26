import Foundation

/// Per-provider quota snapshot. `dailyTokenLimit == nil` means unlimited
/// (true for on-device providers; cloud providers always have a configured limit).
public struct QuotaUsage: Sendable, Equatable {
    public var dailyTokensUsed: Int
    public var dailyTokenLimit: Int?
    public init(dailyTokensUsed: Int, dailyTokenLimit: Int?) {
        self.dailyTokensUsed = dailyTokensUsed
        self.dailyTokenLimit = dailyTokenLimit
    }
    /// `true` when next call would push usage at or beyond the limit.
    /// Conservative — we block at limit, not over, so a 100/100 day still
    /// triggers `.quotaExceeded`.
    public var isExceeded: Bool {
        guard let limit = dailyTokenLimit else { return false }
        return dailyTokensUsed >= limit
    }
}

/// Tracks token-level usage per provider. Phase 0e: in-memory only.
/// Phase 0f: persistent + reset-at-midnight + 80% warning hooks.
public protocol QuotaTracker: Sendable {
    func usage(for provider: ProviderID) async -> QuotaUsage
    func recordUsage(provider: ProviderID, tokens: Int) async
}
