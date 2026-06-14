import Foundation

/// Dedupe/cooldown for proactive insights. A dismissed/shown insight does not
/// re-fire for the same dedupe key until the cooldown elapses.
public final class InsightCooldownStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let now: () -> Date
    private static let prefix = "nexus.insight.cooldown."

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    public func shouldFire(key: String, cooldown: TimeInterval) -> Bool {
        guard let last = defaults.object(forKey: Self.prefix + key) as? Date else { return true }
        return now().timeIntervalSince(last) >= cooldown
    }

    public func record(key: String) {
        defaults.set(now(), forKey: Self.prefix + key)
    }
}
