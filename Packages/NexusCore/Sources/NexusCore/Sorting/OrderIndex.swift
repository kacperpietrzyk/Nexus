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
}
