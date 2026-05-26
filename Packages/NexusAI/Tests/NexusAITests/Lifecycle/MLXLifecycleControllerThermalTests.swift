import Foundation
import Synchronization
import Testing

@testable import NexusAI

// MARK: - Helpers

private func makeThermalStore(_ fn: String) -> ModelManifestLocalState.Store {
    let defaults = UserDefaults(suiteName: "thermal-\(fn)")!
    defaults.removePersistentDomain(forName: "thermal-\(fn)")
    return ModelManifestLocalState.Store(defaults: defaults)
}

// MARK: - Tests

/// `.serious` thermal state marks the controller degraded, empties the chat
/// slot, and leaves the embedder untouched.
@Test func seriousThermalEntersDegradedAndUnloadsChat() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)
    #expect(!ctrl.isThermalDegraded)

    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)

    #expect(ctrl.isThermalDegraded, "serious thermal must set the degraded flag")
    #expect(!ctrl.isChatAvailable, "chat must be unavailable while thermally degraded")
    #expect(ctrl.isEmbedderAvailable, "embedder must not be affected by thermal degradation")
}

/// `.critical` also degrades and empties chat (covers the second heat-state case).
@Test func criticalThermalEntersDegraded() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    ctrl.handleThermalChange(ProcessInfo.ThermalState.critical)

    #expect(ctrl.isThermalDegraded)
    #expect(!ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable, "embedder not gated by critical thermal either")
}

/// `.fair` arms the recovery countdown just like `.nominal` does.
@Test func fairThermalArmsRecoveryCountdown() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    // Put it in degraded state first.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    #expect(ctrl.isThermalDegraded)

    // Transition to .fair — this should arm the nominal countdown.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.fair)

    // Advance clock past recovery window and tick.
    clock.withLock { $0 = $0.addingTimeInterval(0.3) }
    ctrl.tickIdleSweep()

    #expect(!ctrl.isThermalDegraded, ".fair must arm the countdown; recovery must fire after window")
}

/// The chat slot is directly emptied by `.serious` (no-deadlock path proof).
/// After `.serious`, `markChatLoaded` re-populates; a second `.serious` empties again.
@Test func seriousThermalDirectlyEmptiesChatSlot() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()
    #expect(ctrl.isChatAvailable)

    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    // Chat slot must be empty — isChatAvailable is false both due to the
    // thermalDegraded flag AND the slot being physically emptied.
    #expect(!ctrl.isChatAvailable)

    // Clear the thermal flag externally (simulates manual override) — the slot
    // should still be empty because .serious cleared it.
    ctrl.setThermalDegraded(false)
    #expect(!ctrl.isChatAvailable, "slot is empty even after thermal flag is cleared")

    // Re-load and verify embedder was not disturbed throughout.
    ctrl.markChatLoaded()
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)
}

/// Full recovery state-machine: serious → nominal → stable window → recovered.
/// A second `.serious` during countdown cancels recovery (stays degraded).
@Test func recoveryWindowAndCancelBySecondSeriousThermal() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    // Step 1: enter degraded state.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    #expect(ctrl.isThermalDegraded)

    // Step 2: nominal arms the countdown.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.nominal)

    // Step 3: advance clock *less* than the window — tick must NOT recover yet.
    clock.withLock { $0 = $0.addingTimeInterval(0.1) }
    ctrl.tickIdleSweep()
    #expect(ctrl.isThermalDegraded, "window not elapsed — must still be degraded")

    // Step 4: a new `.serious` during the countdown cancels recovery
    // (thermalNominalSince reset to nil).
    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    #expect(ctrl.isThermalDegraded, "second serious — still degraded")

    // Step 5: advance clock past what would have been the original window —
    // tick must NOT recover because the countdown was cancelled by Step 4.
    clock.withLock { $0 = $0.addingTimeInterval(0.15) }
    ctrl.tickIdleSweep()
    #expect(ctrl.isThermalDegraded, "cancelled countdown — must NOT recover on stale elapsed time")

    // Step 6: arm a fresh countdown.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.nominal)

    // Step 7: advance past the full window from the new arm point.
    clock.withLock { $0 = $0.addingTimeInterval(0.25) }
    ctrl.tickIdleSweep()
    #expect(!ctrl.isThermalDegraded, "fresh countdown elapsed — must be recovered")
    #expect(ctrl.isChatAvailable == false, "slot was emptied by .serious; recovery only clears flag")
}

/// Recovery does NOT fire when the device never returned to nominal/fair
/// (thermalNominalSince remains nil).
@Test func recoveryDoesNotFireWithoutNominalTransition() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(10),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    #expect(ctrl.isThermalDegraded)

    // Advance clock way past the window — but we never called handleThermalChange(.nominal).
    clock.withLock { $0 = $0.addingTimeInterval(1.0) }
    ctrl.tickIdleSweep()
    #expect(ctrl.isThermalDegraded, "no nominal transition → thermalNominalSince is nil → no recovery")
}

/// `.nominal` on a non-degraded controller is a no-op (countdown guard:
/// thermalDegraded must be true before nominalSince is set).
@Test func nominalOnNonDegradedControllerIsNoOp() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    // Calling .nominal when not degraded must not flip the flag.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.nominal)
    #expect(!ctrl.isThermalDegraded, "nominal on non-degraded controller must not flip the flag")
    #expect(ctrl.isChatAvailable, "chat unaffected by nominal when not degraded")
    #expect(ctrl.isEmbedderAvailable)
}

/// Pre-existing Task-15 test preserved: setThermalDegraded(true/false) still
/// gates chat but not embedder (backward-compatibility guard).
@Test func legacySetThermalDegradedStillGatesChatButNotEmbedder() {
    let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-\(#function)", directoryHint: .isDirectory),
        localStateStore: makeThermalStore(#function),
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(200),
        nowProvider: { clock.withLock { $0 } },
        startSweep: false
    )

    ctrl.markChatLoaded()
    ctrl.markEmbedderLoaded()

    ctrl.setThermalDegraded(true)
    #expect(!ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)
    #expect(ctrl.isThermalDegraded)

    ctrl.setThermalDegraded(false)
    #expect(ctrl.isChatAvailable)
    #expect(ctrl.isEmbedderAvailable)
    #expect(!ctrl.isThermalDegraded)
}

/// Background-sweep smoke: real sweep + background Task picks up a thermal
/// recovery within a reasonable wall-clock bound. This is the ONE real-sleep
/// test — gated by `.timeLimit` so a regression fails rather than hangs.
@Test(.timeLimit(.minutes(1)))
func backgroundSweepRecoversThermalStateAfterWindow() async throws {
    let fn = "thermal-smoke-\(#function)"
    let defaults = UserDefaults(suiteName: fn)!
    defaults.removePersistentDomain(forName: fn)
    let store = ModelManifestLocalState.Store(defaults: defaults)

    let ctrl = MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-thermal-smoke-\(#function)", directoryHint: .isDirectory),
        localStateStore: store,
        chatIdleTimeout: .seconds(3600),
        embedderIdleTimeout: .seconds(3600),
        thermalRecoveryWindow: .milliseconds(100),
        startSweep: true
    )

    ctrl.handleThermalChange(ProcessInfo.ThermalState.serious)
    #expect(ctrl.isThermalDegraded)

    // Arm recovery.
    ctrl.handleThermalChange(ProcessInfo.ThermalState.nominal)

    // Wait long enough for the 50ms sweep tick to fire at least twice after
    // the 100ms recovery window elapses.
    try await Task.sleep(for: .milliseconds(400))

    #expect(!ctrl.isThermalDegraded, "background sweep must clear thermal degradation after recovery window")
}
