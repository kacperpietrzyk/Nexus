import Foundation

/// Pure helper for drag-drop ordering. `midpoint` returns the `orderIndex` value
/// for a task being inserted between two siblings (or at one end of the list).
public enum OrderIndex {
    /// Returns the order-index value to assign to a task being placed between
    /// `prev` and `next`. Either bound may be `nil` for head/tail insertion;
    /// both `nil` means an empty list. Equal bounds nudge by a fixed epsilon
    /// so the result is strictly greater than `prev` (a safety belt against
    /// degenerate state — the rebalance job is the canonical fix).
    public static func midpoint(prev: Double?, next: Double?) -> Double {
        switch (prev, next) {
        case (nil, nil):
            return 1.0
        case (nil, let n?):
            return n - 1.0
        case (let p?, nil):
            return p + 1.0
        case (let p?, let n?):
            if p == n {
                return p + 0.0001
            }
            return (p + n) / 2.0
        }
    }

    /// Ordering that respects a persisted manual `orderIndex` when present and
    /// otherwise falls back to `dueAt`, then `createdAt`. Tasks with a manual
    /// `orderIndex` sort ahead of un-ordered ones (so a drag-to-reorder sticks);
    /// when no task has been reordered yet, this is exactly the previous
    /// due-date order. Used for the Today bucket so a reorder persists across
    /// reloads instead of being overwritten by a pure `dueAt` sort.
    public static func manualThenDueOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.orderIndex, rhs.orderIndex) {
        case (let left?, let right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        switch (lhs.dueAt, rhs.dueAt) {
        case (let left?, let right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }
}
