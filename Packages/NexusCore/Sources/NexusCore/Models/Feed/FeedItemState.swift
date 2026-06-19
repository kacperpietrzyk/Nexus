import Foundation
import SwiftData

/// Mutable per-feed-item UI state (seen / dismissed / snoozed), keyed by a
/// stable derived `key` (e.g. "meeting:<uuid>", "brief:2026-06-19"). Unlike the
/// append-only `ActivityEntry`, this is upserted as state transitions. Synced
/// (CloudKit private DB) so "have I seen this" agrees across devices.
///
/// NOT `Linkable`/`Searchable` — it is UI metadata about projected feed items,
/// not a graph item. No `@Attribute(.unique)` on `key` (the CloudKit mirror
/// rejects unique constraints); duplicates from a sync race are collapsed in
/// `FeedItemStateRepository.upsert` (newest `updatedAt` wins).
@Model
public final class FeedItemState {
    public var key: String = ""
    public var seenAt: Date?
    public var dismissedAt: Date?
    public var snoozedUntil: Date?
    public var updatedAt: Date = Date.now

    public init(
        key: String,
        seenAt: Date? = nil,
        dismissedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.seenAt = seenAt
        self.dismissedAt = dismissedAt
        self.snoozedUntil = snoozedUntil
        self.updatedAt = updatedAt
    }
}
