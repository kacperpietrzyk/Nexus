import Combine
import Foundation
import NexusCore

/// Probes WCSession reachability and the freshness of the last iPhone ping.
/// Concrete adopter wraps a real `WCSession`; tests inject an in-memory fake.
protocol WatchReachabilityProbing: AnyObject, Sendable {
    var isReachable: Bool { get }
    var lastIPhonePing: Date? { get }
}

/// Loads the most recent `NotificationSnapshot` pushed from the iPhone.
/// Production adopter is `WatchNotificationSnapshotStore`; tests inject an
/// in-memory fake.
protocol WatchSnapshotLoading: AnyObject, Sendable {
    func load() -> NotificationSnapshot?
}

/// Loads the user-configured `QuietHours` from the App Group store. Production
/// adopter is `UserDefaultsQuietHoursStore`; tests inject an in-memory fake.
protocol QuietHoursLoading: AnyObject, Sendable {
    func load() -> QuietHours?
}

extension WatchNotificationSnapshotStore: WatchSnapshotLoading {}
extension UserDefaultsQuietHoursStore: QuietHoursLoading {}

/// Owns the install/uninstall decision for `WatchNotificationScheduler`.
///
/// Decision table (see spec §5.3):
///
/// | Reachability | Last iPhone ping age | Action                                  |
/// |--------------|----------------------|-----------------------------------------|
/// | reachable    | < 90s                | `uninstallAll` (iPhone is the master)   |
/// | reachable    | ≥ 90s or nil         | `uninstallAll` (treat as iPhone master) |
/// | unreachable  | < 90s                | debounce + schedule delayed re-evaluate |
/// | unreachable  | ≥ 90s or nil         | install local triggers from snapshot    |
///
/// The debounce branch is load-bearing: the Watch in background may not
/// receive timer ticks, so the guard self-schedules a follow-up `evaluate()`
/// after the remaining debounce window so a freshly-disconnected Watch is
/// not stranded without alarms.
@MainActor
final class WatchNotificationGuard {
    private static let debounceWindow: TimeInterval = 90

    private let snapshotStore: any WatchSnapshotLoading
    private let scheduler: WatchNotificationScheduler
    private let probe: any WatchReachabilityProbing
    private let quietHoursStore: any QuietHoursLoading
    private let nowProvider: @Sendable () -> Date

    private var timerCancellable: AnyCancellable?
    private var pendingDelayedTask: _Concurrency.Task<Void, Never>?
    private var installedSnapshotGeneratedAt: Date?

    /// Exposed for tests. `true` when the guard is in the debounce window and
    /// has scheduled a follow-up `evaluate()` task.
    var hasPendingDelayedEvaluation: Bool { pendingDelayedTask != nil }

    init(
        snapshotStore: any WatchSnapshotLoading,
        scheduler: WatchNotificationScheduler,
        probe: any WatchReachabilityProbing,
        quietHoursStore: any QuietHoursLoading,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.snapshotStore = snapshotStore
        self.scheduler = scheduler
        self.probe = probe
        self.quietHoursStore = quietHoursStore
        self.nowProvider = now
    }

    /// Starts a 60s tick that re-evaluates the install/uninstall decision.
    /// Foreground-only: the Watch will not deliver timer ticks while the app
    /// is suspended, which is why the debounce branch self-schedules a
    /// follow-up via `Task.sleep` independent of this timer.
    func startTimer() {
        timerCancellable = Foundation.Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                _Concurrency.Task { @MainActor [weak self] in
                    await self?.evaluate()
                }
            }
    }

    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Evaluates the decision table and either installs or uninstalls Watch
    /// reminders. Cancels any pending delayed re-evaluation so we don't stack
    /// follow-ups.
    func evaluate() async {
        pendingDelayedTask?.cancel()
        pendingDelayedTask = nil

        let now = nowProvider()
        let reachable = probe.isReachable
        let lastPing = probe.lastIPhonePing
        let pingAge = lastPing.map { now.timeIntervalSince($0) }

        if reachable {
            // Reachable: iPhone is master regardless of ping age. Drop any
            // stale Watch-installed triggers.
            await scheduler.uninstallAll()
            installedSnapshotGeneratedAt = nil
            return
        }
        if let pingAge, pingAge < Self.debounceWindow {
            // Unreachable but the iPhone was just here -- debounce so a brief
            // glitch doesn't double-fire alarms. Self-schedule a follow-up
            // after the remaining window because the timer may be paused.
            let delay = max(0, Self.debounceWindow + 1 - pingAge)
            pendingDelayedTask = _Concurrency.Task { @MainActor [weak self] in
                try? await _Concurrency.Task.sleep(for: .seconds(delay))
                await self?.evaluate()
            }
            return
        }
        // Unreachable + stale (or no) ping: Watch becomes the local master.
        guard let snapshot = snapshotStore.load() else { return }
        if installedSnapshotGeneratedAt == snapshot.generatedAt { return }
        let quiet = quietHoursStore.load()
        do {
            try await scheduler.install(snapshot: snapshot, quietHours: quiet)
            installedSnapshotGeneratedAt = snapshot.generatedAt
        } catch {
            installedSnapshotGeneratedAt = nil
        }
    }
}
