import Foundation

/// Seam for "the system calendar database changed" (`EKEventStoreChanged`).
/// EventKit stays isolated in `EventKitCalendarProvider`; consumers (the
/// calendar view-model / composition roots) register through this protocol so
/// the M1 auto-replan pipeline is testable with `MockCalendarChangeObserver`.
public protocol CalendarChangeObserving: Sendable {
    /// Register `handler` to run on every store change. Returns the observation
    /// token; the caller retains it for the observation's lifetime and removes
    /// it (`NotificationCenter.default.removeObserver`) on teardown.
    @discardableResult
    func observeStoreChanges(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol
}
