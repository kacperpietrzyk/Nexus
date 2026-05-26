import Foundation
import Synchronization

#if canImport(UIKit)
import UIKit
#endif

/// Responds to OS memory-pressure signals by unloading MLX model slots in
/// order of cost:
///
/// 1. Chat model is **always** unloaded on the first warning (highest VRAM
///    cost, short-lived sessions).
/// 2. The embedder (~1 GB multilingual-e5-large) is **kept** unless the system
///    is genuinely starved — signalled by either two warnings within a 60-second
///    window OR a `.critical` severity warning.
///
/// ## Observer lifecycle
/// On iOS the actor registers a `UIApplication.didReceiveMemoryWarningNotification`
/// observer in `init` via a one-shot `Task`. The observer token is stored in a
/// `Mutex<NSObjectProtocol?>` (the same pattern used by `MLXLifecycleController`
/// for its sweep task) so that `deinit` can remove it from `NotificationCenter`
/// without crossing actor isolation. The registration closure captures
/// `[weak self]`, and the inner `Task` also uses `[weak self]`, preventing the
/// guard from being pinned alive by the run loop.
///
/// macOS memory-pressure observer (DispatchSource `.memoryPressure` /
/// NSWorkspace) is added in a later task if needed.
public actor MLXMemoryGuard {

    // MARK: - Types

    /// Severity level passed by the OS (or in tests).
    public enum Severity: Sendable {
        /// Normal memory-pressure warning — chat unloads; embedder kept unless
        /// two warnings arrive within ``doubleWarningWindow`` seconds.
        case normal
        /// Critical memory pressure — chat AND embedder unload immediately.
        case critical
    }

    // MARK: - Private state

    private let lifecycle: MLXLifecycleController

    /// Timestamps of recent `.normal` warnings used for the double-warning
    /// 60-second escalation window.
    private var recentWarnings: [Date] = []

    /// Duration (seconds) within which two `.normal` warnings trigger embedder
    /// unload. Embedder is worth keeping unless the system is genuinely starved.
    private let doubleWarningWindow: TimeInterval = 60

    /// Produces the current date. Injectable for deterministic tests.
    private let nowProvider: @Sendable () -> Date

    /// Stores the `NotificationCenter` observer token so `deinit` can remove
    /// it. Stored in a `Mutex` so the actor-isolated `registerObservers()` can
    /// write to it and the non-isolated `deinit` can read from it — the same
    /// pattern `MLXLifecycleController` uses for its `sweepTask`.
    private let observerToken: Mutex<NSObjectProtocol?> = Mutex(nil)

    // MARK: - Init

    public init(
        lifecycle: MLXLifecycleController,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.lifecycle = lifecycle
        self.nowProvider = nowProvider

        // One-shot Task that completes after registration; it does not run
        // indefinitely so it does not extend the guard's lifetime. The inner
        // [weak self] ensures that if the guard deinits before the Task
        // executes, registration is simply skipped.
        Task { [weak self] in
            await self?.registerObservers()
        }
    }

    deinit {
        // Remove the NotificationCenter observer so the guard leaves no dangling
        // callback behind. `observerToken` is a `let Mutex`, accessible from
        // non-isolated deinit without crossing actor isolation.
        observerToken.withLock { token in
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    // MARK: - Observer registration

    /// Registers the OS memory-warning notification observer.
    ///
    /// Idempotent: a second call is a no-op if a token is already stored.
    private func registerObservers() {
        #if canImport(UIKit)
        observerToken.withLock { token in
            guard token == nil else { return }  // idempotency guard
            token = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                // Hop onto the actor asynchronously; [weak self] prevents
                // the Task from anchoring the guard past deinit.
                Task { [weak self] in
                    await self?.handleMemoryWarning(severity: .normal)
                }
            }
        }
        #else
        // macOS DispatchSource.memoryPressure / NSWorkspace observer wired in Task 18.
        #endif
    }

    // MARK: - Core logic

    /// Handles a memory warning.
    ///
    /// - Always unloads chat first (highest VRAM cost).
    /// - Prunes `recentWarnings` entries older than ``doubleWarningWindow``.
    /// - Appends the current timestamp.
    /// - If `recentWarnings.count >= 2` OR `severity == .critical`, also
    ///   unloads the embedder and clears `recentWarnings`.
    public func handleMemoryWarning(severity: Severity) {
        // 1. Chat always unloads first (no await — MLXLifecycleController is sync).
        lifecycle.unloadChat()

        // 2. Prune warnings outside the window.
        let now = nowProvider()
        recentWarnings = recentWarnings.filter {
            now.timeIntervalSince($0) < doubleWarningWindow
        }

        // 3. Record this warning.
        recentWarnings.append(now)

        // 4. Escalate if the system is genuinely starved.
        let shouldUnloadEmbedder = recentWarnings.count >= 2 || severity == .critical
        if shouldUnloadEmbedder {
            lifecycle.unloadEmbedder()
            recentWarnings.removeAll()
        }
    }
}
