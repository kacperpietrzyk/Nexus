import Foundation
import SwiftData

/// Per-provider, per-day token usage log. Inserted by `PersistentQuotaTracker`
/// each time a provider invocation completes (Phase 1a).
///
/// `day` is the start-of-day in user's local calendar, used as bucket key for
/// daily-quota aggregation. Multiple `QuotaLog` rows with the same
/// `(providerRaw, day)` accumulate — `PersistentQuotaTracker` sums them.
///
/// CloudKit-friendly: every property has a default and there are no required
/// relationships. Following the same pattern as `Link` / `DebugItem` /
/// `ConflictLog`, `id` is **not** marked `@Attribute(.unique)` because CloudKit
/// mirroring forbids unique constraints.
@Model
public final class QuotaLog {
    public var id: UUID = UUID()
    public var providerRaw: String = ""
    public var day: Date = Date.now
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0

    public init(
        id: UUID = UUID(),
        providerRaw: String,
        day: Date,
        promptTokens: Int,
        completionTokens: Int
    ) {
        self.id = id
        self.providerRaw = providerRaw
        self.day = day
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public var totalTokens: Int { promptTokens + completionTokens }
}
