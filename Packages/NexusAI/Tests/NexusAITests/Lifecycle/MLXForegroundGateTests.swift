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
    initiallyForeground: Bool,
    chatIdleTimeout: Duration = .seconds(120),
    nowProvider: @escaping @Sendable () -> Date = { Date() }
) -> MLXLifecycleController {
    MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-mlx-fg-\(fn)", directoryHint: .isDirectory),
        localStateStore: makeStore(fn),
        chatIdleTimeout: chatIdleTimeout,
        nowProvider: nowProvider,
        initiallyForeground: initiallyForeground,
        startSweep: false
    )
}

/// Records whether the loader closure was ever invoked, so a gated path can be
/// asserted to have refused BEFORE any (real-world: GPU-submitting) load.
private final class LoadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var loaded = false
    func markLoaded() { lock.withLock { loaded = true } }
    var wasLoaded: Bool { lock.withLock { loaded } }
}

private final class StubChat: MLXChatGenerating, @unchecked Sendable {
    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text("ok"))
            continuation.finish()
        }
    }
    func unload() async {}
}

private final class StubEmbedder: MLXEmbedderGenerating, @unchecked Sendable {
    func embed(text: String) async throws -> [Float] { [0.0, 1.0] }
    func unload() async {}
}

// MARK: - Lifecycle gate state

@Suite("MLX foreground gate (issue #51)")
struct MLXForegroundGateTests {
    @Test("setForegroundActive toggles the synchronous accessor")
    func toggles() {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        #expect(!ctrl.isForegroundActive)

        ctrl.setForegroundActive(true)
        #expect(ctrl.isForegroundActive)

        ctrl.setForegroundActive(false)
        #expect(!ctrl.isForegroundActive)
    }

    @Test("macOS platform default opens the gate")
    func macOSDefaultIsOpen() {
        #if os(macOS)
        #expect(MLXLifecycleController.defaultInitialForeground())
        #else
        #expect(!MLXLifecycleController.defaultInitialForeground())
        #endif
    }

    // MARK: - Chat engine

    @Test("chat generate refuses (no load) while backgrounded")
    func chatGenerateRefusesBackgrounded() async {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let probe = LoadProbe()
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _, _ in
            probe.markLoaded()
            return StubChat()
        }

        await #expect(throws: MLXChatEngineError.self) {
            _ = try await engine.generate(
                messages: [MLXChatMessage(role: .user, text: "hi")],
                tools: [],
                params: .default
            )
        }
        #expect(!probe.wasLoaded, "the loader must not run when the gate is closed")
    }

    @Test("chat preload refuses (no load) while backgrounded")
    func chatPreloadRefusesBackgrounded() async {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let probe = LoadProbe()
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _, _ in
            probe.markLoaded()
            return StubChat()
        }

        await #expect(throws: MLXChatEngineError.self) {
            try await engine.preload()
        }
        #expect(!probe.wasLoaded)
    }

    @Test("chat generate proceeds once the gate is open")
    func chatGenerateProceedsForeground() async throws {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _, _ in StubChat() }

        ctrl.setForegroundActive(true)
        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "hi")],
            tools: [],
            params: .default
        )
        var sawText = false
        for try await chunk in stream {
            if case .text = chunk { sawText = true }
        }
        #expect(sawText)
    }

    // MARK: - Embedder engine

    @Test("embedder embed refuses (no load) while backgrounded")
    func embedderEmbedRefusesBackgrounded() async {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let probe = LoadProbe()
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _ in
            probe.markLoaded()
            return StubEmbedder()
        }

        await #expect(throws: MLXEmbedderEngineError.self) {
            _ = try await engine.embed(text: "hi")
        }
        #expect(!probe.wasLoaded)
    }

    @Test("embedder preload refuses (no load) while backgrounded")
    func embedderPreloadRefusesBackgrounded() async {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let probe = LoadProbe()
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _ in
            probe.markLoaded()
            return StubEmbedder()
        }

        await #expect(throws: MLXEmbedderEngineError.self) {
            try await engine.preload()
        }
        #expect(!probe.wasLoaded)
    }

    @Test("embedder embed proceeds once the gate is open")
    func embedderEmbedProceedsForeground() async throws {
        let ctrl = makeController(fn: #function, initiallyForeground: false)
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _ in StubEmbedder() }

        ctrl.setForegroundActive(true)
        let vector = try await engine.embed(text: "hi")
        #expect(vector == [0.0, 1.0])
    }

    // MARK: - Known limitation: idle-sweep then re-foreground does NOT re-warm

    /// Pins the documented limitation (issue #51 PR note): the scenePhase
    /// `.active` warmup fires `preload`, which after an idle sweep hits
    /// `loadIfNeeded`'s cached-container fast path and does NOT
    /// `markChatLoaded()` (re-warm must route through `reload()`). So a model
    /// swept while backgrounded stays unavailable on return until relaunch —
    /// the router falls back rather than re-warming on-device. This is a
    /// PRE-EXISTING property (nothing re-warmed before either), not a
    /// regression; the test exists so the limitation is asserted, not
    /// rediscovered.
    @Test("idle-swept chat is not re-warmed by a second foreground preload")
    func idleSweptChatNotRewarmedByPreload() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let ctrl = makeController(
            fn: #function,
            initiallyForeground: true,
            chatIdleTimeout: .milliseconds(100),
            nowProvider: { clock.withLock { $0 } }
        )
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: ctrl
        ) { _, _ in StubChat() }

        // First foreground warmup loads + marks the slot.
        try await engine.preload()
        #expect(ctrl.isChatAvailable)

        // Background long enough for the idle sweep to empty the slot.
        clock.withLock { $0 = $0.addingTimeInterval(0.2) }
        ctrl.tickIdleSweep()
        #expect(!ctrl.isChatAvailable)

        // Return to foreground: a second preload hits the cached-container fast
        // path and does NOT re-mark — the slot stays empty (the limitation).
        try await engine.preload()
        #expect(!ctrl.isChatAvailable)
    }

    // MARK: - No-gate path

    @Test("nil lifecycle proceeds (no gate)")
    func nilLifecycleProceeds() async throws {
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: nil
        ) { _ in StubEmbedder() }

        let vector = try await engine.embed(text: "hi")
        #expect(vector == [0.0, 1.0])
    }
}
