import Foundation

extension Sequence where Element == TaskItem {
    /// Collapses rows that share a `TaskItem.id`, keeping the first occurrence and
    /// preserving order.
    ///
    /// Defends the read path against a historical data pathology on synced stores:
    /// a single logical task can be materialized as **two** rows with the SAME `id`
    /// — one under the current `TaskItem` entity and one left under a stale entity
    /// number by an older schema migration, each with its own CloudKit record. Both
    /// then mirror down, so every list shows the task twice. Until the duplicate
    /// rows are physically purged, this keeps the display honest (one row per `id`)
    /// without any destructive write. Idempotent and a no-op on a clean store.
    public func dedupedByID() -> [TaskItem] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.id).inserted }
    }
}
