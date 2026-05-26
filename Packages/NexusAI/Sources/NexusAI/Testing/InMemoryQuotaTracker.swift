import Foundation

// MARK: - For testing only
//
// Counter-style quota tracker. No clock — `recordUsage` accumulates forever.
// Tests that need "midnight reset" semantics will wrap the real persistent
// tracker landing in Phase 0f.

public actor InMemoryQuotaTracker: QuotaTracker {
    private var used: [ProviderID: Int] = [:]
    private let limits: [ProviderID: Int]

    public init(dailyTokenLimit: [ProviderID: Int] = [:]) {
        self.limits = dailyTokenLimit
    }

    public func usage(for provider: ProviderID) -> QuotaUsage {
        QuotaUsage(
            dailyTokensUsed: used[provider, default: 0],
            dailyTokenLimit: limits[provider]
        )
    }

    public func recordUsage(provider: ProviderID, tokens: Int) {
        used[provider, default: 0] += tokens
    }
}
