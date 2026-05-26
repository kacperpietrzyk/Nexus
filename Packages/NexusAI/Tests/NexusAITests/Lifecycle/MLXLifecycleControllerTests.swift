import Foundation
import Synchronization
import Testing

@testable import NexusAI

// MARK: - Helpers

private func makeStore(_ fn: String) -> ModelManifestLocalState.Store {
    let defaults = UserDefaults(suiteName: fn)!
    defaults.removePersistentDomain(forName: fn)
    return ModelManifestLocalState.Store(defaults: defaults)
}

private func makeController(
    fn: String,
    chatIdleTimeout: Duration = .milliseconds(200),
    embedderIdleTimeout: Duration = .milliseconds(500),
    nowProvider: @escaping @Sendable () -> Date = { Date() },
    startSweep: Bool = false
) -> MLXLifecycleController {
    MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-mlxlc-\(fn)", directoryHint: .isDirectory),
        localStateStore: makeStore(fn),
        chatIdleTimeout: chatIdleTimeout,
        embedderIdleTimeout: embedderIdleTimeout,
        nowProvider: nowProvider,
        startSweep: startSweep
    )
}

// MARK: - Idle sweep tests (deterministic, no wall-clock)

@Test func chatUnloadsAfterIdleTimeout() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = makeController(
        fn: #function,
        chatIdleTimeout: .milliseconds(100),
        nowProvider: { clock.withLock { $0 } }
    )

    ctrl.markChatLoaded()
    #expect(ctrl.isChatAvailable)

    // Advance clock past the 100ms chat idle timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.2) }
    ctrl.tickIdleSweep()

    #expect(!ctrl.isChatAvailable)
}

@Test func embedderNotSweptWhenOnlyChatTimesOut() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = makeController(
        fn: #function,
        chatIdleTimeout: .milliseconds(100),
        embedderIdleTimeout: .milliseconds(500),
        nowProvider: { clock.withLock { $0 } }
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)

    // Advance past chat timeout but well under embedder timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.2) }
    ctrl.tickIdleSweep()

    #expect(!ctrl.isChatAvailable, "chat should be swept after its timeout")
    #expect(ctrl.isEmbedderAvailable, "embedder timeout has not elapsed yet")
}

@Test func embedderUnloadsAfterIdleTimeout() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = makeController(
        fn: #function,
        embedderIdleTimeout: .milliseconds(100),
        nowProvider: { clock.withLock { $0 } }
    )

    ctrl.markEmbedderLoaded()
    #expect(ctrl.isEmbedderAvailable)

    // Advance clock past the 100ms embedder idle timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.2) }
    ctrl.tickIdleSweep()

    #expect(!ctrl.isEmbedderAvailable)
}

@Test func manualUnloadClearsBothSlots() {
    let ctrl = makeController(fn: #function)

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)

    ctrl.unloadAll()

    #expect(!ctrl.isChatAvailable)
    #expect(!ctrl.isEmbedderAvailable)
}

@Test func touchChatResetsIdleClock() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = makeController(
        fn: #function,
        chatIdleTimeout: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } }
    )

    ctrl.markChatLoaded()

    // Advance to near (but under) the timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.15) }

    // Touch resets idleSince to current clock value (0.15s).
    ctrl.touchChat()

    // Advance by another 0.1s: total elapsed = 0.25s, but since touch = 0.1s < 0.2s timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.1) }
    ctrl.tickIdleSweep()

    #expect(ctrl.isChatAvailable, "chat should still be available because touch reset the idle clock")

    // Advance by another 0.15s so since-touch = 0.25s > 0.2s timeout.
    clock.withLock { $0 = $0.addingTimeInterval(0.15) }
    ctrl.tickIdleSweep()

    #expect(!ctrl.isChatAvailable, "chat should now be swept after touch timeout elapsed")
}

@Test func touchChatOnEmptySlotLeavesSlotEmpty() {
    let ctrl = makeController(fn: #function)

    // Slot is empty — touch must NOT promote it to loaded.
    ctrl.touchChat()
    #expect(!ctrl.isChatAvailable)

    // load → sweep to empty → touch must not resurrect the slot.
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl2 = makeController(
        fn: "\(#function)_2",
        chatIdleTimeout: .milliseconds(100),
        nowProvider: { clock.withLock { $0 } }
    )
    ctrl2.markChatLoaded()
    clock.withLock { $0 = $0.addingTimeInterval(0.2) }
    ctrl2.tickIdleSweep()
    #expect(!ctrl2.isChatAvailable, "precondition: slot swept to empty")
    ctrl2.touchChat()
    #expect(!ctrl2.isChatAvailable, "touch after sweep must not promote an empty slot")
}

@Test func touchEmbedderOnEmptySlotLeavesSlotEmpty() {
    let ctrl = makeController(fn: #function)

    // Slot is empty — touch must NOT promote it to loaded.
    ctrl.touchEmbedder()
    #expect(!ctrl.isEmbedderAvailable)

    // load → sweep to empty → touch must not resurrect the slot.
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl2 = makeController(
        fn: "\(#function)_2",
        embedderIdleTimeout: .milliseconds(100),
        nowProvider: { clock.withLock { $0 } }
    )
    ctrl2.markEmbedderLoaded()
    clock.withLock { $0 = $0.addingTimeInterval(0.2) }
    ctrl2.tickIdleSweep()
    #expect(!ctrl2.isEmbedderAvailable, "precondition: slot swept to empty")
    ctrl2.touchEmbedder()
    #expect(!ctrl2.isEmbedderAvailable, "touch after sweep must not promote an empty slot")
}

@Test func thermalDegradeGatesChatButNotEmbedder() {
    let ctrl = makeController(fn: #function)

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)

    ctrl.setThermalDegraded(true)

    #expect(!ctrl.isChatAvailable, "thermal degradation should gate chat availability")
    #expect(ctrl.isEmbedderAvailable, "thermal degradation should not affect embedder")

    ctrl.setThermalDegraded(false)

    #expect(ctrl.isChatAvailable, "clearing thermal flag restores chat availability")
    #expect(ctrl.isEmbedderAvailable)
}

@Test func individualUnloadLeavesOtherSlotIntact() {
    let ctrl = makeController(fn: #function)

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    ctrl.unloadChat()

    #expect(!ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)

    ctrl.markChatLoaded()
    ctrl.unloadEmbedder()

    #expect(ctrl.isChatAvailable)
    #expect(!ctrl.isEmbedderAvailable)
}

// MARK: - Folder URL resolution

@Test func chatFolderURLUsesUnknownFallback() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nexus-folder-\(#function)", directoryHint: .isDirectory)
    let store = makeStore(#function)  // empty store → no assignment
    let ctrl = MLXLifecycleController(
        modelsRoot: root,
        localStateStore: store,
        startSweep: false
    )

    let url = ctrl.chatFolderURL()
    #expect(url.lastPathComponent == "unknown")
    #expect(url.deletingLastPathComponent().path == root.path)
}

@Test func embedderFolderURLUsesE5Fallback() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nexus-folder-\(#function)", directoryHint: .isDirectory)
    let store = makeStore(#function)  // empty store → no assignment
    let ctrl = MLXLifecycleController(
        modelsRoot: root,
        localStateStore: store,
        startSweep: false
    )

    let url = ctrl.embedderFolderURL()
    #expect(url.lastPathComponent == "multilingual-e5-large")
    #expect(url.deletingLastPathComponent().path == root.path)
}

@Test func chatFolderURLUsesAssignment() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "nexus-folder-\(#function)", directoryHint: .isDirectory)
    let store = makeStore(#function)
    var manifest = ModelManifestLocalState()
    manifest.assignedAsChat = true
    store.save(manifestID: "qwen3.5-4b-instruct-4bit", state: manifest)

    let ctrl = MLXLifecycleController(
        modelsRoot: root,
        localStateStore: store,
        startSweep: false
    )

    let url = ctrl.chatFolderURL()
    #expect(url.lastPathComponent == "qwen3.5-4b-instruct-4bit")
}

// MARK: - Real-sleep background sweep smoke

@Test(.timeLimit(.minutes(1)))
func backgroundSweepAutoUnloadsChatAfterIdleTimeout() async throws {
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-sweep-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeStore(#function),
        chatIdleTimeout: .milliseconds(100),
        startSweep: true
    )

    ctrl.markChatLoaded()
    #expect(ctrl.isChatAvailable)

    // Wait long enough for the background sweep (50ms tick) to fire at least
    // twice after the 100ms idle timeout elapses.
    try await Task.sleep(for: .milliseconds(300))

    #expect(!ctrl.isChatAvailable)
}

// MARK: - Deinit / weak-self sweep leak guard

@Test(.timeLimit(.minutes(1)))
func controllerDeallocatesWithActiveSweep() async throws {
    // Create the controller inside a scope so it can deinit after the scope exits.
    weak var weakCtrl: MLXLifecycleController?
    do {
        let ctrl = MLXLifecycleController(
            modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "nexus-deinit-\(#function)", directoryHint: .isDirectory),
            localStateStore: makeStore(#function),
            startSweep: true
        )
        weakCtrl = ctrl
        ctrl.markChatLoaded()
        // Verify it is live before we drop it.
        #expect(weakCtrl != nil)
    }
    // The sweep Task is inside a `Task { [weak self] in … }` and suspends on
    // `try? await Task.sleep(for: .milliseconds(50))`. We need the run loop to
    // turn at least once so the sweep's suspension frame is released, allowing
    // the controller's refcount to reach zero and ARC to deinit it.
    // deinit calls sweepTask.withLock { $0?.cancel() } which stops the sweep.
    try await Task.sleep(for: .milliseconds(80))
    #expect(weakCtrl == nil, "controller should be deallocated — sweep Task uses [weak self]")
}
