import Foundation
import Synchronization

/// Per-slot (chat, embedder) lifecycle state machine.
///
/// Each slot is ``Slot/empty`` or ``Slot/loaded(idleSince:)``. A background
/// idle sweep auto-unloads a slot after its platform-default idle timeout:
///
/// - Chat: iOS 120 s / macOS 600 s (active chat sessions are expected to be
///   shorter-lived so memory is reclaimed sooner).
/// - Embedder: 3 600 s (1 h — embedder weights are used for search/retrieval
///   and stay relevant across many operations).
///
/// ``isChatAvailable`` and ``isEmbedderAvailable`` are synchronous,
/// non-suspending accessors backed by a ``Synchronization/Mutex`` so they can
/// be called safely from the ``AIRouter`` availability hot path without
/// hopping an actor or a cooperative thread.
///
/// Engine teardown (actually unloading weights from memory) is handled by a
/// later task; this type manages *state* only.
public final class MLXLifecycleController: Sendable {

    // MARK: - Types

    /// The lifecycle state of a single model slot.
    public enum Slot: Sendable, Equatable {
        /// No model is loaded in this slot.
        case empty
        /// A model is loaded; `idleSince` records the last time the slot was
        /// touched (used to compute idle duration for the background sweep).
        case loaded(idleSince: Date)
    }

    // MARK: - Private state

    private struct State {
        var chat: Slot = .empty
        var embedder: Slot = .empty
        /// When `true`, ``isChatAvailable`` returns `false` even if the slot
        /// is `.loaded` — used for thermal backpressure.
        var thermalDegraded = false
        /// Set to `nowProvider()` when the device returns to nominal/fair
        /// thermal state while `thermalDegraded` is still `true`. Recovery
        /// is confirmed by the idle sweep once the stable window elapses.
        /// Cleared back to `nil` if the device heats up again before the
        /// window expires, resetting the countdown.
        var thermalNominalSince: Date?
        /// Whether the app is currently foreground-active. When `false`, every
        /// MLX GPU entry point (chat preload/generate, embedder preload/embed)
        /// MUST refuse to dispatch: Metal command buffers submitted while the
        /// app is not foreground are rejected by the OS
        /// (`kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted`),
        /// and MLX surfaces that as an uncatchable C++ `throw` →
        /// `std::terminate` → SIGABRT on its internal serial queue (issue #51).
        /// Prevention at dispatch time is the only fix. Defaults `true` on
        /// macOS (no background-GPU restriction) and `false` elsewhere (the
        /// scene is not active at launch; the scenePhase observer opens the
        /// gate once the app is genuinely `.active`).
        ///
        /// The struct default is overwritten by `init` from the
        /// `initiallyForeground` parameter; it exists only so `State()` is
        /// default-constructible for the `Mutex(State())` stored initializer.
        var foregroundActive = true
    }

    private let state = Mutex(State())
    private let modelsRoot: URL
    private let localStateStore: ModelManifestLocalState.Store
    private let chatIdleTimeout: Duration
    private let embedderIdleTimeout: Duration
    private let thermalRecoveryWindow: Duration
    private let nowProvider: @Sendable () -> Date

    /// Holds the background sweep task so `deinit` can cancel it.
    /// Wrapped in a `Mutex` so the assignment from `init` is Sendable-clean.
    private let sweepTask: Mutex<Task<Void, Never>?> = Mutex(nil)

    /// Stores the `NotificationCenter` observer token for the thermal-state
    /// notification so `deinit` can remove it without crossing isolation.
    /// Mirrors the pattern used by `MLXMemoryGuard.observerToken`.
    private let thermalObserverToken: Mutex<NSObjectProtocol?> = Mutex(nil)

    // MARK: - Init

    public init(
        modelsRoot: URL,
        localStateStore: ModelManifestLocalState.Store,
        chatIdleTimeout: Duration = MLXLifecycleController.chatDefaultTimeout(),
        embedderIdleTimeout: Duration = .seconds(3600),
        thermalRecoveryWindow: Duration = .seconds(300),
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        /// Initial foreground-gate state. Defaults to the platform default
        /// (``defaultInitialForeground()``: `true` on macOS, `false`
        /// elsewhere). Tests override it to exercise the gate on the macOS
        /// host without a real scene.
        initiallyForeground: Bool = MLXLifecycleController.defaultInitialForeground(),
        /// Pass `false` in tests to drive the idle sweep deterministically via
        /// ``tickIdleSweep()`` instead of relying on wall-clock timing.
        startSweep: Bool = true
    ) {
        self.modelsRoot = modelsRoot
        self.localStateStore = localStateStore
        self.chatIdleTimeout = chatIdleTimeout
        self.embedderIdleTimeout = embedderIdleTimeout
        self.thermalRecoveryWindow = thermalRecoveryWindow
        self.nowProvider = nowProvider
        self.state.withLock { $0.foregroundActive = initiallyForeground }

        if startSweep {
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    // Guard lets the sweep end naturally when the controller is
                    // deallocated — the weak reference goes nil and the Task exits,
                    // rather than extending the controller's lifetime.
                    guard let self else { return }
                    self.tickIdleSweep()
                }
            }
            sweepTask.withLock { $0 = task }

            #if os(iOS)
            thermalObserverToken.withLock { token in
                guard token == nil else { return }
                token = NotificationCenter.default.addObserver(
                    forName: ProcessInfo.thermalStateDidChangeNotification,
                    object: nil,
                    queue: nil
                ) { [weak self] _ in
                    // handleThermalChange is sync + Mutex-guarded + Sendable-safe.
                    // No actor hop or Task wrapper needed or desired here.
                    self?.handleThermalChange(ProcessInfo.processInfo.thermalState)
                }
            }
            #endif
        }
    }

    deinit {
        // Cancel the background sweep so it stops referencing self after deinit.
        sweepTask.withLock { $0?.cancel() }

        #if os(iOS)
        thermalObserverToken.withLock { token in
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }
        #endif
    }

    // MARK: - Platform-default timeout

    public static func chatDefaultTimeout() -> Duration {
        #if os(iOS)
        return .seconds(120)
        #else
        return .seconds(600)
        #endif
    }

    /// Platform default for the foreground gate (issue #51). macOS has no
    /// background-GPU restriction, so the gate starts open; every other
    /// platform starts closed (the scene is not `.active` at launch) and is
    /// opened by the app's scenePhase observer via ``setForegroundActive(_:)``.
    public static func defaultInitialForeground() -> Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Availability (sync, zero suspension points)

    /// Whether the chat slot has a loaded model and the device is not under
    /// thermal pressure.
    ///
    /// This is a synchronous accessor with no `await` — safe to call from the
    /// ``AIRouter`` availability hot path on any thread.
    public var isChatAvailable: Bool {
        state.withLock { s in
            guard !s.thermalDegraded else { return false }
            if case .loaded = s.chat { return true }
            return false
        }
    }

    /// Whether the embedder slot has a loaded model.
    ///
    /// Embedder availability is not gated by thermal pressure because
    /// embedding calls are short and infrequent compared to chat inference.
    public var isEmbedderAvailable: Bool {
        state.withLock { s in
            if case .loaded = s.embedder { return true }
            return false
        }
    }

    // MARK: - Slot lifecycle

    /// Marks the chat slot as loaded, recording `now` as the idle baseline.
    public func markChatLoaded() {
        state.withLock { $0.chat = .loaded(idleSince: nowProvider()) }
    }

    /// Marks the embedder slot as loaded, recording `now` as the idle baseline.
    public func markEmbedderLoaded() {
        state.withLock { $0.embedder = .loaded(idleSince: nowProvider()) }
    }

    /// Refreshes the chat slot's idle timestamp to prevent a sweep while the
    /// model is actively being used.
    ///
    /// No-op when the slot is ``Slot/empty`` — touch must not promote an empty
    /// slot to loaded, which would report phantom availability before the engine
    /// has actually loaded any weights.
    public func touchChat() {
        state.withLock { s in
            guard case .loaded = s.chat else { return }
            s.chat = .loaded(idleSince: nowProvider())
        }
    }

    /// Refreshes the embedder slot's idle timestamp.
    ///
    /// No-op when the slot is ``Slot/empty`` — same phantom-availability guard
    /// as ``touchChat()``.
    public func touchEmbedder() {
        state.withLock { s in
            guard case .loaded = s.embedder else { return }
            s.embedder = .loaded(idleSince: nowProvider())
        }
    }

    /// Clears the chat slot state. Actual engine teardown is handled elsewhere
    /// (Task 17); this method only mutates the availability state.
    public func unloadChat() {
        state.withLock { $0.chat = .empty }
    }

    /// Clears the embedder slot state.
    public func unloadEmbedder() {
        state.withLock { $0.embedder = .empty }
    }

    /// Clears both slots atomically.
    public func unloadAll() {
        state.withLock {
            $0.chat = .empty
            $0.embedder = .empty
        }
    }

    // MARK: - Foreground gate (issue #51)

    /// Whether MLX GPU work may be dispatched right now.
    ///
    /// Synchronous, zero-suspension accessor backed by the `Mutex<State>` —
    /// callable from the engine GPU entry points on any thread/actor without an
    /// actor hop. When `false`, the engines refuse to submit Metal command
    /// buffers (which the OS rejects in the background, crashing the process via
    /// MLX's uncatchable C++ `throw`).
    public var isForegroundActive: Bool {
        state.withLock { $0.foregroundActive }
    }

    /// Opens or closes the foreground gate. Driven by the app's scenePhase
    /// observer: `true` on `.active`, `false` on `.inactive`/`.background`.
    public func setForegroundActive(_ active: Bool) {
        state.withLock { $0.foregroundActive = active }
    }

    // MARK: - Thermal backpressure

    /// Controls thermal backpressure for the chat slot.
    ///
    /// When `true`, ``isChatAvailable`` returns `false` even if the slot is
    /// `.loaded`, causing ``AIRouter`` to skip on-device chat inference and
    /// fall back to cloud or Apple Foundation Models.
    public func setThermalDegraded(_ flag: Bool) {
        state.withLock { $0.thermalDegraded = flag }
    }

    /// Whether the device is currently in a thermally-degraded state.
    ///
    /// Synchronous, zero-suspension accessor backed by the `Mutex<State>`.
    /// Mirrors the shape of ``isChatAvailable``.
    public var isThermalDegraded: Bool {
        state.withLock { $0.thermalDegraded }
    }

    /// Responds to a `ProcessInfo.ThermalState` change.
    ///
    /// - `.serious` / `.critical`: marks the controller degraded and empties
    ///   the chat slot immediately. The embedder slot is left untouched because
    ///   embedding calls are short and infrequent.
    /// - `.nominal` / `.fair`: arms the recovery countdown by recording
    ///   `nowProvider()` in `thermalNominalSince`. Actual recovery (clearing
    ///   `thermalDegraded`) happens in ``tickIdleSweep()`` once the stable
    ///   window has elapsed without another heat event.
    ///
    /// This method is fully synchronous and platform-universal. Only the
    /// `ProcessInfo.thermalStateDidChangeNotification` *registration* is
    /// iOS-only (in `init`).
    ///
    /// ## Deadlock safety
    /// `Mutex.withLock` is not reentrant. This method mutates `State` fields
    /// **directly** inside one `withLock` closure and does **not** call
    /// `unloadChat()`, `setThermalDegraded()`, or any other method that would
    /// acquire the same lock — doing so would self-deadlock the calling thread.
    public func handleThermalChange(_ thermalState: ProcessInfo.ThermalState) {
        // Capture `now` outside the lock to keep the closure minimal and
        // free of any nested calls that could acquire the same mutex.
        let now = nowProvider()
        state.withLock { s in
            switch thermalState {
            case .serious, .critical:
                s.thermalDegraded = true
                s.thermalNominalSince = nil
                // Set chat slot empty directly — calling `unloadChat()` here
                // would re-enter the mutex and deadlock.
                s.chat = .empty
            case .nominal, .fair:
                // Only arm the countdown when we are actually degraded and
                // the countdown has not already been started.
                if s.thermalDegraded && s.thermalNominalSince == nil {
                    s.thermalNominalSince = now
                }
            @unknown default:
                break
            }
        }
    }

    // MARK: - Folder URL resolution

    /// The local filesystem folder where the current chat model weights live.
    ///
    /// Resolves the currently-assigned manifest ID from `localStateStore`;
    /// falls back to `"unknown"` when no assignment is recorded.
    public func chatFolderURL() -> URL {
        let id = localStateStore.currentChatAssignment() ?? "unknown"
        return modelsRoot.appending(path: id, directoryHint: .isDirectory)
    }

    /// The local filesystem folder where the current embedder model weights live.
    ///
    /// Falls back to `ModelCatalog.defaultEmbedderID` when no assignment is
    /// recorded (that is the only supported embedder model as of Phase 1l).
    public func embedderFolderURL() -> URL {
        let id = localStateStore.currentEmbedderAssignment() ?? ModelCatalog.defaultEmbedderID
        return modelsRoot.appending(path: id, directoryHint: .isDirectory)
    }

    // MARK: - Idle sweep

    /// Runs one idle-sweep pass.
    ///
    /// Called by the background `Task` every 50 ms (production) or directly in
    /// tests with `startSweep: false` for deterministic control.
    ///
    /// In addition to idle-timeout eviction, this pass also evaluates thermal
    /// recovery: if the device has been at `nominal`/`fair` thermal state for
    /// at least `thermalRecoveryWindow`, the `thermalDegraded` flag is cleared.
    ///
    /// Recovery is intentionally tick-driven rather than implemented as a
    /// separate countdown `Task`. A countdown `Task` would reintroduce an
    /// unstored-mutable-`Task` data race and produce wall-clock-flaky tests —
    /// the very problems the Task-15 reshape eliminated. The ≤50 ms sweep
    /// cadence means recovery is detected within one tick after the 5-minute
    /// window elapses, which is operationally irrelevant slack.
    func tickIdleSweep() {
        let now = nowProvider()
        state.withLock { s in
            s.chat = idleSlot(s.chat, timeout: chatIdleTimeout, now: now)
            s.embedder = idleSlot(s.embedder, timeout: embedderIdleTimeout, now: now)

            // Thermal recovery: clear degraded flag once the device has
            // remained at nominal/fair temperature for the full recovery window.
            let windowElapsed =
                s.thermalNominalSince.map {
                    now.timeIntervalSince($0) >= thermalRecoveryWindow.totalSeconds
                } ?? false
            if s.thermalDegraded && windowElapsed {
                s.thermalDegraded = false
                s.thermalNominalSince = nil
            }
        }
    }

    /// Returns `.empty` when the slot has been idle for at least `timeout`,
    /// otherwise returns the slot unchanged.
    private func idleSlot(_ slot: Slot, timeout: Duration, now: Date) -> Slot {
        guard case .loaded(let idleSince) = slot else { return slot }
        return now.timeIntervalSince(idleSince) >= timeout.totalSeconds ? .empty : slot
    }
}

// MARK: - Duration helpers

extension Duration {
    /// Wall-clock seconds as a `TimeInterval`, sub-second precision preserved.
    ///
    /// The plan originally used `Duration.components.seconds` (an `Int`), which
    /// silently truncates sub-second timeouts — e.g. `.milliseconds(100)` would
    /// compare as `0` seconds and never fire. This extension avoids the trap by
    /// combining the integer seconds with the attosecond remainder.
    var totalSeconds: TimeInterval {
        let c = components
        // attoseconds: 1e-18 seconds each. 1e17 attoseconds = 100 ms.
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
