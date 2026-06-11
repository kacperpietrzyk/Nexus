import Foundation

/// In-memory `CalendarChangeObserving` fake (the `MockCalendarWriter` pattern:
/// lock-guarded, `@unchecked Sendable`). Tests call `fireChange()` to simulate
/// an `EKEventStoreChanged` broadcast.
public final class MockCalendarChangeObserver: CalendarChangeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [@Sendable () -> Void] = []

    public init() {}

    @discardableResult
    public func observeStoreChanges(_ handler: @escaping @Sendable () -> Void) -> NSObjectProtocol {
        locked { handlers.append(handler) }
        return NSObject()
    }

    /// Simulate a store-change broadcast: synchronously invoke every handler.
    public func fireChange() {
        let snapshot = locked { handlers }
        for handler in snapshot {
            handler()
        }
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
