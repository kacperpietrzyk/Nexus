import Foundation

/// Shared "quiet mode" gate that lets an external agent bracket a burst of writes
/// (`batch.begin` … `batch.end`) so the app does not re-run its store-change
/// refresh fan-out on every intermediate save.
///
/// ## What it actually suppresses
/// When the app is parked off the Today tab, the LLM Daily-Brief regeneration is
/// already unmounted and never fires (`LiquidTodayScreen.reloadOnStoreChange`).
/// What still fires per-save is the *shell* refresh fan-out
/// (`ContentView.dashboardChrome.reloadOnStoreChange`: activity-feed unread
/// re-projection + navigation entity-command rebuild — both 400 ms debounced).
/// This coordinator suppresses *that* fan-out (and the brief too, if Today is
/// mounted) during a batch, then fires exactly one `resumed` signal when the
/// batch ends so the final state is reloaded once.
///
/// ## Why ref-counted-global, not per-connection
/// The suppression point — the `ModelContext.didSave` /
/// `NSPersistentStoreRemoteChange` observer in `reloadOnStoreChange` — carries no
/// connection identity, and there is exactly ONE UI refresh path. A store change
/// cannot be attributed to the MCP connection that caused it, and registry tools
/// (`batch.begin`/`batch.end`) receive only the shared `AgentContext`, not the
/// originating socket FD. So a per-connection suspend is not reachable from the
/// place that must honor it. Instead we ref-count: each `begin` increments, each
/// `end` decrements, and the refresh resumes on the true 1→0 transition.
///
/// ### Documented race (bounded + cheap)
/// With concurrent MCP sessions (Task 1), session B's writes during session A's
/// batch are also coalesced into A's batch window, so B's parked-mode refresh is
/// deferred until A's batch ends (or the self-expiry deadline, whichever comes
/// first). This is acceptable because (a) the suppressed work is the cheap fan-out,
/// not the LLM brief, and (b) the suspend is hard-bounded by `expiryInterval` — a
/// crash or dropped `end_batch` mid-batch can never wedge refresh off forever.
///
/// ## Crash safety / self-expiry
/// Every `begin` (re)arms a sliding deadline `expiryInterval` into the future. If
/// no `end` arrives before the deadline, `expireIfElapsed(now:)` forces the count
/// back to 0 and resumes. `end` is idempotent: an `end` with no outstanding
/// `begin` is a no-op that never fires a spurious resume.
///
/// The type is `@MainActor` (all SwiftData store-change observers hop to the main
/// actor before consulting it) and split into pure decision logic — unit-tested
/// without timers — plus a thin Timer/NotificationCenter shell.
@MainActor
public final class RefreshSuspensionCoordinator {

    /// Posted exactly once when an active batch resolves (last `end`, or expiry).
    /// Store-change observers re-run their (coalesced) reload on receipt so the
    /// final post-batch state is loaded once.
    public static let resumedNotification = Notification.Name("com.nexus.refreshSuspension.resumed")

    /// Default sliding self-expiry window. Long enough to bracket a realistic
    /// write series (dozens of MCP tool calls), short enough that a dropped
    /// `end_batch` only parks refresh briefly. Re-armed on every `begin`.
    public static let defaultExpiryInterval: TimeInterval = 90

    public static let shared = RefreshSuspensionCoordinator()

    private let expiryInterval: TimeInterval
    private let clock: @MainActor () -> Date
    private let onResume: @MainActor () -> Void

    private var depth = 0
    private var deadline: Date?
    private var expiryTimer: Timer?

    /// - Parameters:
    ///   - expiryInterval: sliding self-expiry window, re-armed on each `begin`.
    ///   - clock: injectable now-provider (tests drive it without sleeping).
    ///   - onResume: fired on a true resume transition. Defaults to posting
    ///     `resumedNotification` on the default center; tests inject a spy.
    public init(
        expiryInterval: TimeInterval = RefreshSuspensionCoordinator.defaultExpiryInterval,
        clock: @escaping @MainActor () -> Date = { Date() },
        onResume: @escaping @MainActor () -> Void = {
            NotificationCenter.default.post(name: RefreshSuspensionCoordinator.resumedNotification, object: nil)
        }
    ) {
        self.expiryInterval = expiryInterval
        self.clock = clock
        self.onResume = onResume
    }

    /// True while at least one batch is open AND its deadline has not elapsed.
    /// Store-change observers check this before running their refresh; `true`
    /// means "swallow this refresh, it will be coalesced into the batch resume".
    /// Reading it also lazily expires a stale batch (covers the case where no
    /// timer fired — e.g. the process was suspended), so a missed `end` can never
    /// leave this stuck `true`.
    public var isSuspended: Bool {
        expireIfElapsed(now: clock())
        return depth > 0
    }

    /// Opens a batch. Increments the ref-count and (re)arms the sliding deadline.
    public func begin() {
        beginPure(now: clock())
        armTimer()
    }

    /// Closes a batch. Decrements the ref-count (floored at 0). Idempotent: an
    /// `end` with no outstanding `begin` is a safe no-op. Returns whether this
    /// call resolved the last open batch (i.e. fired a resume).
    @discardableResult
    public func end() -> Bool {
        let resumed = endPure(now: clock())
        if resumed { fireResume() }
        return resumed
    }

    // MARK: - Pure decision core (unit-tested without timers)

    /// Increments depth and re-arms the deadline. Returns the new depth.
    @discardableResult
    func beginPure(now: Date) -> Int {
        // A new begin overrides any elapsed-but-not-yet-collected deadline.
        expireIfElapsedPure(now: now)
        depth += 1
        deadline = now.addingTimeInterval(expiryInterval)
        return depth
    }

    /// Decrements depth (floored at 0). Returns `true` iff this transitioned an
    /// active batch (depth ≥ 1) down to 0 — the only case that resumes refresh.
    /// `end` below 0 (never began) returns `false` without side effects.
    func endPure(now: Date) -> Bool {
        // If the batch already expired, the resume already fired; this end is a
        // no-op tail.
        if expireIfElapsedPure(now: now) {
            return false
        }
        guard depth > 0 else { return false }
        depth -= 1
        if depth == 0 {
            deadline = nil
            return true
        }
        return false
    }

    /// Public, timer-independent expiry hook. Returns `true` if it forced an
    /// active batch to resume. Fires the resume side effect when it does.
    @discardableResult
    public func expireIfElapsed(now: Date) -> Bool {
        let resumed = expireIfElapsedPure(now: now)
        if resumed { fireResume() }
        return resumed
    }

    /// Pure expiry: if a deadline exists and `now` is past it, force depth→0 and
    /// report a resume. No side effects.
    @discardableResult
    private func expireIfElapsedPure(now: Date) -> Bool {
        guard let deadline, depth > 0, now >= deadline else { return false }
        depth = 0
        self.deadline = nil
        return true
    }

    // MARK: - Timer / side-effect shell

    private func fireResume() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        onResume()
    }

    private func armTimer() {
        expiryTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: expiryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.expireIfElapsed(now: self.clock())
            }
        }
        expiryTimer = timer
    }
}
