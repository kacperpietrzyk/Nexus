import Foundation

/// Sendable abstraction over time so scheduler logic is unit-testable without sleeping.
public protocol JobClock: Sendable {
    func now() -> Date
}

/// Production clock — wraps `Date.now`.
public struct SystemJobClock: JobClock {
    public init() {}
    public func now() -> Date { .now }
}

/// Test clock — manually advanced. Threadsafe via internal lock.
public final class FakeJobClock: JobClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(start: Date) {
        self.current = start
    }

    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}
