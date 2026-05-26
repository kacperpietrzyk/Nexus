import Foundation

public final class BGTaskCompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var didComplete = false

    public init() {}

    @discardableResult
    public func complete(success: Bool, _ complete: (Bool) -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didComplete else { return false }

        didComplete = true
        complete(success)
        return true
    }
}
