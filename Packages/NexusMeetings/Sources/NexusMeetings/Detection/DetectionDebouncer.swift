import Foundation

public final class DetectionDebouncer: @unchecked Sendable {
    private let window: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var emittedAtByFingerprint: [String: Date] = [:]

    public init(window: TimeInterval = 60, now: @escaping @Sendable () -> Date = Date.init) {
        self.window = window
        self.now = now
    }

    public func canEmit(fingerprint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let stamp = now()
        guard let previousStamp = emittedAtByFingerprint[fingerprint] else {
            return true
        }
        if stamp.timeIntervalSince(previousStamp) < window {
            return false
        }

        return true
    }

    public func recordEmit(fingerprint: String) {
        lock.lock()
        defer { lock.unlock() }

        emittedAtByFingerprint[fingerprint] = now()
    }

    public func shouldEmit(fingerprint: String) -> Bool {
        guard canEmit(fingerprint: fingerprint) else {
            return false
        }

        recordEmit(fingerprint: fingerprint)
        return true
    }

    public func reset(fingerprint: String) {
        lock.lock()
        defer { lock.unlock() }

        emittedAtByFingerprint.removeValue(forKey: fingerprint)
    }
}
