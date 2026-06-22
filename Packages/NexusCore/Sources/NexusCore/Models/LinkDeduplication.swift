import Foundation

extension Sequence where Element == Link {
    /// Collapses rows that share a `Link.id`, keeping the first occurrence and
    /// preserving order.
    ///
    /// Defends the read path against a historical data pathology on synced stores:
    /// a single logical link can be materialized as **two** rows with the SAME `id`
    /// — one under the current `Link` entity and one left under a stale entity
    /// number by an older schema migration, each with its own CloudKit record. Both
    /// then mirror down, so every backlinks/outgoing query returns the edge twice.
    /// Until the duplicate rows are physically purged, this keeps the output honest
    /// (one row per `id`) without any destructive write. Idempotent and a no-op on a
    /// clean store.
    public func dedupedByID() -> [Link] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}
