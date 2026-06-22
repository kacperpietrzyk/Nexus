import Foundation

extension Sequence where Element == Meeting {
    /// Collapses rows that share a `Meeting.id`, keeping the first occurrence and
    /// preserving order.
    ///
    /// Defends the read path against a historical data pathology on synced stores:
    /// a single logical meeting can be materialized as **two** rows with the SAME `id`
    /// — one under the current `Meeting` entity and one left under a stale entity
    /// number by an older schema migration, each with its own CloudKit record. Both
    /// then mirror down, so list queries return the meeting twice. Until the duplicate
    /// rows are physically purged, this keeps the output honest (one row per `id`)
    /// without any destructive write. Idempotent and a no-op on a clean store.
    public func dedupedByID() -> [Meeting] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}
