import Foundation
import Synchronization
import Testing

@testable import NexusAI

// MARK: - Helpers

private func makeGuardController(fn: String) -> MLXLifecycleController {
    let defaults = UserDefaults(suiteName: fn)!
    defaults.removePersistentDomain(forName: fn)
    let store = ModelManifestLocalState.Store(defaults: defaults)
    return MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-mg-\(fn)", directoryHint: .isDirectory),
        localStateStore: store,
        startSweep: false
    )
}

// MARK: - Single normal warning: chat only

@Test func iosMemoryWarningUnloadsChatOnly() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)

    let memGuard = MLXMemoryGuard(lifecycle: ctrl)
    await memGuard.handleMemoryWarning(severity: .normal)

    #expect(!ctrl.isChatAvailable, "chat must be unloaded on first .normal warning")
    #expect(ctrl.isEmbedderAvailable, "embedder must survive a single .normal warning")
}

// MARK: - Double warning within window: both unloaded

@Test func doubleMemoryWarningUnloadsEmbedderToo() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    // Both warnings at the same logical time — within the 60s window.
    let frozenNow = Date(timeIntervalSinceReferenceDate: 1_000)
    let memGuard = MLXMemoryGuard(lifecycle: ctrl, nowProvider: { frozenNow })

    await memGuard.handleMemoryWarning(severity: .normal)
    // Reload chat slot so we can confirm it's unloaded a second time too.
    ctrl.markChatLoaded()
    await memGuard.handleMemoryWarning(severity: .normal)

    #expect(!ctrl.isChatAvailable, "chat must be unloaded on second warning")
    #expect(!ctrl.isEmbedderAvailable, "embedder must be unloaded after two warnings within 60s")
}

// MARK: - .critical: escalates on first warning

@Test func criticalSeverityUnloadsEmbedderOnFirstWarning() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    let memGuard = MLXMemoryGuard(lifecycle: ctrl)
    await memGuard.handleMemoryWarning(severity: .critical)

    #expect(!ctrl.isChatAvailable, "chat must be unloaded on .critical warning")
    #expect(!ctrl.isEmbedderAvailable, "embedder must be unloaded on .critical warning (first warning)")
}

// MARK: - 60-second window pruning: stale warning does not count

@Test func staleWarningBeyondWindowDoesNotTriggerEmbedderUnload() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    // Simulate two warnings 70 seconds apart — beyond the 60s window.
    // The guard uses an injectable nowProvider for determinism.
    let clockMutex = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let memGuard = MLXMemoryGuard(lifecycle: ctrl, nowProvider: { clockMutex.withLock { $0 } })

    // First warning at t=0: chat unloaded, recentWarnings = [t=0], count=1 → embedder kept.
    await memGuard.handleMemoryWarning(severity: .normal)
    #expect(!ctrl.isChatAvailable, "chat must be unloaded on first warning")
    #expect(ctrl.isEmbedderAvailable, "embedder must survive first warning")

    // Reload chat to prep for second warning.
    ctrl.markChatLoaded()

    // Advance clock 70 seconds (past the 60s window).
    clockMutex.withLock { $0 = $0.addingTimeInterval(70) }

    // Second warning at t=70: prune removes the t=0 entry (>60s ago); append t=70 →
    // recentWarnings = [t=70], count=1 → embedder must still be kept.
    await memGuard.handleMemoryWarning(severity: .normal)
    #expect(!ctrl.isChatAvailable, "chat must be unloaded on second (stale-pruned) warning")
    #expect(ctrl.isEmbedderAvailable, "embedder must survive because the first warning was pruned as stale")
}

// MARK: - Third warning after prune does NOT escalate

@Test func thirdWarningAfterPruneDoesNotEscalate() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    let clockMutex = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let memGuard = MLXMemoryGuard(lifecycle: ctrl, nowProvider: { clockMutex.withLock { $0 } })

    // t=0: first normal warning — chat unloads, count=1.
    await memGuard.handleMemoryWarning(severity: .normal)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    // t=70: beyond window — prune removes t=0 entry, count becomes 1 not 2.
    clockMutex.withLock { $0 = $0.addingTimeInterval(70) }
    await memGuard.handleMemoryWarning(severity: .normal)

    // Embedder must still be available: window pruning kept count=1, not 2.
    #expect(ctrl.isEmbedderAvailable, "embedder must remain loaded: stale warning was pruned, window count = 1")
}

// MARK: - .critical clears recentWarnings; subsequent .normal is a fresh slate

@Test func criticalClearsWarningHistory() async {
    let ctrl = makeGuardController(fn: #function)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    let frozenNow = Date(timeIntervalSinceReferenceDate: 500)
    let memGuard = MLXMemoryGuard(lifecycle: ctrl, nowProvider: { frozenNow })

    // .critical: unloads both AND clears history.
    await memGuard.handleMemoryWarning(severity: .critical)
    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    // Next .normal warning: history was cleared, so count=1 → embedder kept.
    await memGuard.handleMemoryWarning(severity: .normal)
    #expect(!ctrl.isChatAvailable, "chat must be unloaded")
    #expect(ctrl.isEmbedderAvailable, "embedder must survive: .critical cleared history, first .normal starts fresh")
}

// MARK: - Weak-ref / deinit: guard can be dropped without leaking

@Test(.timeLimit(.minutes(1)))
func guardDeallocatesAndObserverTokenIsRemoved() async {
    // This test verifies that a created-and-dropped guard does not leak:
    // the actor deinit removes the observer token from NotificationCenter.
    // We use a weak reference to detect ARC release.
    let ctrl = makeGuardController(fn: #function)
    weak var weakGuard: MLXMemoryGuard?

    do {
        let memGuard = MLXMemoryGuard(lifecycle: ctrl)
        weakGuard = memGuard
        #expect(weakGuard != nil, "precondition: guard is alive inside the scope")
    }
    // No retain cycle exists: NotificationCenter holds the observer token
    // opaquely, the observer closure captures [weak self], and the init Task
    // also captures [weak self] — so the actor deallocates once the last strong
    // reference (memGuard, above) drops at end-of-scope. Two cooperative yields
    // give the Swift concurrency scheduler a chance to drain the actor's executor
    // queue without depending on wall-clock timing. This is best-effort
    // ARC-timing observation; on a heavily loaded CI host the assertion may need
    // to be replaced with a side-effect spy (e.g., observing the observer-token
    // removal path), but it is NOT proven by a comment in deinit.
    await Task.yield()
    await Task.yield()
    #expect(weakGuard == nil, "MLXMemoryGuard must deinit once its last strong reference is dropped (no retain cycle).")
}
