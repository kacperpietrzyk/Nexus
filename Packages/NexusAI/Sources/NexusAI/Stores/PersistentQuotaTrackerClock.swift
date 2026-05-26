import Foundation

/// Injectable clock for `PersistentQuotaTracker` — mirrors the `JobClock`
/// pattern from Phase 0e Scheduler. Tests inject a fixed clock; production
/// uses `Date()`.
public protocol PersistentQuotaTrackerClock: Sendable {
    func current() -> Date
}

/// Production clock — wraps `Date()`.
public struct SystemPersistentQuotaTrackerClock: PersistentQuotaTrackerClock {
    public init() {}
    public func current() -> Date { Date() }
}
