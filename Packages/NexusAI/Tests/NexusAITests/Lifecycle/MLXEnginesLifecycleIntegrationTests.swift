import Foundation
import Synchronization
import Testing

@testable import NexusAI

// MARK: - Shared helpers (mirrors makeController in MLXLifecycleControllerTests.swift)

private func makeStore(_ fn: String) -> ModelManifestLocalState.Store {
    let defaults = UserDefaults(suiteName: fn)!
    defaults.removePersistentDomain(forName: fn)
    return ModelManifestLocalState.Store(defaults: defaults)
}

private func makeLifecycle(
    fn: String,
    chatIdleTimeout: Duration = .milliseconds(200),
    embedderIdleTimeout: Duration = .milliseconds(500),
    nowProvider: @escaping @Sendable () -> Date = { Date() }
) -> MLXLifecycleController {
    MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(
                path: "nexus-engine-lc-\(fn)",
                directoryHint: .isDirectory
            ),
        localStateStore: makeStore(fn),
        chatIdleTimeout: chatIdleTimeout,
        embedderIdleTimeout: embedderIdleTimeout,
        nowProvider: nowProvider,
        startSweep: false
    )
}

// MARK: - Stub doubles

/// Trivial synchronous chat stub — never parks, never fails.
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

/// Trivial embedding stub.
private final class StubEmbedder: MLXEmbedderGenerating, @unchecked Sendable {
    func embed(text: String) async throws -> [Float] { [0.1, 0.2, 0.3] }
    func unload() async {}
}

/// Tracks how many times `unload()` was called; used to prove orphan cleanup.
private final class UnloadCountingEmbedder: MLXEmbedderGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var unloadCount: Int { lock.withLock { count } }
    func embed(text: String) async throws -> [Float] { [9.0] }
    func unload() async { lock.withLock { count += 1 } }
}

/// Suspending gate: `park()` blocks until `release()` is called. Used to race
/// an in-flight embedder load with `unload()` deterministically.
private actor LoadGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func park() async {
        if released { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func release() {
        guard !released else { return }
        released = true
        waiter?.resume()
        waiter = nil
    }
}

private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
    func bump() -> Int { count += 1; return count }
}

// MARK: - Chat engine ↔ lifecycle integration tests

@Suite("MLXChatEngine ↔ MLXLifecycleController wiring")
struct MLXChatEngineLifecycleTests {

    // MARK: markChatLoaded fires on the genuine cached-load success point

    @Test("markChatLoaded fires after the container is committed to cache")
    func markChatLoadedOnCacheCommit() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let lifecycle = makeLifecycle(
            fn: #function,
            chatIdleTimeout: .milliseconds(200),
            nowProvider: { clock.withLock { $0 } }
        )

        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }

        // Before any generate call the slot is empty.
        #expect(!lifecycle.isChatAvailable)

        // Trigger the load via the public generate entrypoint.
        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "hi")],
            tools: [],
            params: .default
        )
        // Drain to ensure the load completes.
        var chunks: [MLXChunk] = []
        for try await chunk in stream { chunks.append(chunk) }

        // After the cold load, the lifecycle slot must be marked loaded.
        #expect(lifecycle.isChatAvailable, "markChatLoaded must fire on the cold load path")
    }

    // MARK: touchChat resets idle clock so active conversations are not swept

    @Test("touchChat on generate resets idle clock, preventing mid-conversation sweep")
    func touchChatResetsIdleOnGenerate() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let lifecycle = makeLifecycle(
            fn: #function,
            chatIdleTimeout: .milliseconds(200),
            nowProvider: { clock.withLock { $0 } }
        )

        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }

        // Warm up so markChatLoaded fires and the slot is loaded.
        let warmStream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "warm")],
            tools: [],
            params: .default
        )
        for try await _ in warmStream {}
        #expect(lifecycle.isChatAvailable, "precondition: slot loaded")

        // Advance clock to just under the 200ms idle timeout.
        clock.withLock { $0 = $0.addingTimeInterval(0.15) }
        lifecycle.tickIdleSweep()
        #expect(lifecycle.isChatAvailable, "precondition: not yet swept")

        // Now generate again — touchChat fires at the start, resetting idleSince
        // to the current clock (0.15 s).
        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "second")],
            tools: [],
            params: .default
        )
        for try await _ in stream {}

        // Advance another 0.1 s: total from epoch = 0.25 s, but since-touch = 0.1 s
        // which is less than the 0.2 s timeout.
        clock.withLock { $0 = $0.addingTimeInterval(0.1) }
        lifecycle.tickIdleSweep()
        #expect(
            lifecycle.isChatAvailable,
            "slot must still be available because touch reset the idle clock"
        )

        // Advance another 0.15 s: since-touch = 0.25 s > 0.2 s timeout → sweep fires.
        clock.withLock { $0 = $0.addingTimeInterval(0.15) }
        lifecycle.tickIdleSweep()
        #expect(
            !lifecycle.isChatAvailable,
            "slot must be swept after touch timeout elapsed"
        )
    }

    // MARK: swept-but-resident slot is re-promoted on the cached-hit fast path

    @Test("preload re-marks a swept-but-still-resident chat slot loaded again")
    func preloadRePromotesSweptResidentChatSlot() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let lifecycle = makeLifecycle(
            fn: #function,
            chatIdleTimeout: .milliseconds(200),
            nowProvider: { clock.withLock { $0 } }
        )

        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }

        // Cold load via generate so the container is cached and the slot loaded.
        let warmStream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "warm")],
            tools: [],
            params: .default
        )
        for try await _ in warmStream {}
        #expect(lifecycle.isChatAvailable, "precondition: slot loaded after cold load")

        // Advance past the idle timeout and sweep: the slot goes `.empty` while
        // the engine's `container` stays resident (sweep mutates state only).
        clock.withLock { $0 = $0.addingTimeInterval(0.3) }
        lifecycle.tickIdleSweep()
        #expect(!lifecycle.isChatAvailable, "precondition: slot swept to empty")

        // An ungated `preload()` (e.g. on foreground return) hits the cached
        // container fast path, which must re-promote the resident container.
        try await engine.preload()
        #expect(
            lifecycle.isChatAvailable,
            "cached-hit fast path must re-mark the swept-but-resident slot loaded"
        )
    }

    // MARK: existing call sites unaffected by nil-default lifecycle param

    @Test("engine with nil lifecycle (default) still generates correctly")
    func nilLifecycleDefaultCompiles() async throws {
        // Existing init without lifecycle — must compile and pass unchanged.
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null")
        ) { _, _ in StubChat() }

        let stream = try await engine.generate(
            messages: [MLXChatMessage(role: .user, text: "hi")],
            tools: [],
            params: .default
        )
        var texts: [String] = []
        for try await chunk in stream {
            if case .text(let value) = chunk { texts.append(value) }
        }
        #expect(texts == ["ok"])
    }
}

// MARK: - Embedder engine ↔ lifecycle integration tests

@Suite("MLXEmbedderEngine ↔ MLXLifecycleController wiring")
struct MLXEmbedderEngineLifecycleTests {

    // MARK: markEmbedderLoaded fires on the winning (non-stale) load path

    @Test("markEmbedderLoaded fires after the winning load commits to cache")
    func markEmbedderLoadedOnWinningPath() async throws {
        let lifecycle = makeLifecycle(fn: #function)

        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-lc-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in StubEmbedder() }
        )

        #expect(!lifecycle.isEmbedderAvailable, "precondition: empty before first embed")

        // Trigger the load via the public embed entrypoint.
        _ = try await engine.embed(text: "hello")

        #expect(
            lifecycle.isEmbedderAvailable,
            "markEmbedderLoaded must fire on the winning load path"
        )
    }

    // MARK: touchEmbedder resets idle clock on every embed call

    @Test("touchEmbedder on embed resets idle clock, preventing mid-use sweep")
    func touchEmbedderResetsIdleOnEmbed() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let lifecycle = makeLifecycle(
            fn: #function,
            embedderIdleTimeout: .milliseconds(200),
            nowProvider: { clock.withLock { $0 } }
        )

        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-lc-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in StubEmbedder() }
        )

        // Warm up to fire markEmbedderLoaded.
        _ = try await engine.embed(text: "warm")
        #expect(lifecycle.isEmbedderAvailable, "precondition: loaded")

        // Advance to just under the timeout.
        clock.withLock { $0 = $0.addingTimeInterval(0.15) }
        lifecycle.tickIdleSweep()
        #expect(lifecycle.isEmbedderAvailable, "precondition: not yet swept")

        // Embed again — touchEmbedder resets idleSince to 0.15 s.
        _ = try await engine.embed(text: "second")

        // Advance another 0.1 s: since-touch = 0.1 s < 0.2 s → still live.
        clock.withLock { $0 = $0.addingTimeInterval(0.1) }
        lifecycle.tickIdleSweep()
        #expect(
            lifecycle.isEmbedderAvailable,
            "slot must still be available because touchEmbedder reset the idle clock"
        )

        // Advance another 0.15 s: since-touch = 0.25 s > 0.2 s → swept.
        clock.withLock { $0 = $0.addingTimeInterval(0.15) }
        lifecycle.tickIdleSweep()
        #expect(
            !lifecycle.isEmbedderAvailable,
            "slot must be swept after touch timeout elapsed"
        )
    }

    // MARK: markEmbedderLoaded does NOT fire on the stale/epoch-rejected path

    @Test(
        "markEmbedderLoaded must NOT fire on the epoch-rejected (stale) load path",
        .timeLimit(.minutes(1))
    )
    func markEmbedderLoadedNotFiredOnStalePath() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let gate = LoadGate()
        let counter = LoadCounter()
        let orphan = UnloadCountingEmbedder()

        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-lc-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in
                let number = await counter.bump()
                if number == 1 {
                    // First (gated) load: park until the test triggers unload.
                    await gate.park()
                    return orphan  // this is the stale result the engine must reject
                }
                return StubEmbedder()
            }
        )

        // Start the first embed — its loader parks at the gate.
        async let parked: [Float] = engine.embed(text: "parked")

        // Wait deterministically until the loader is truly in-flight (count == 1).
        while await counter.count < 1 { await Task.yield() }

        // unload() races the in-flight load, bumping loadGeneration.
        await engine.unload()

        // Release the parked loader — its result must be epoch-rejected (not cached).
        await gate.release()
        // The caller still gets its result (the orphaned embedding is returned).
        _ = try await parked

        // KEY ASSERTION: slot must remain EMPTY because markEmbedderLoaded must
        // not fire on the stale/epoch-rejected path (where the container is
        // immediately unloaded without being cached).
        #expect(
            !lifecycle.isEmbedderAvailable,
            "markEmbedderLoaded must NOT fire on the stale/epoch-rejected path"
        )

        // Verify the orphan was unloaded (existing engine invariant confirmed).
        #expect(orphan.unloadCount == 1, "orphan container must be unloaded")
    }

    // MARK: swept-but-resident slot is re-promoted on the cached-hit fast path

    @Test("embed re-marks a swept-but-still-resident embedder slot loaded again")
    func embedRePromotesSweptResidentEmbedderSlot() async throws {
        let clock = Mutex(Date(timeIntervalSinceReferenceDate: 0))
        let lifecycle = makeLifecycle(
            fn: #function,
            embedderIdleTimeout: .milliseconds(200),
            nowProvider: { clock.withLock { $0 } }
        )

        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-lc-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in StubEmbedder() }
        )

        // Cold load via embed so the container is cached and the slot loaded.
        _ = try await engine.embed(text: "warm")
        #expect(lifecycle.isEmbedderAvailable, "precondition: slot loaded after cold load")

        // Advance past the idle timeout and sweep: the slot goes `.empty` while
        // the engine's `container` stays resident (sweep mutates state only).
        clock.withLock { $0 = $0.addingTimeInterval(0.3) }
        lifecycle.tickIdleSweep()
        #expect(!lifecycle.isEmbedderAvailable, "precondition: slot swept to empty")

        // A subsequent embed hits the cached container fast path, which must
        // re-promote the resident container so availability flips back true.
        _ = try await engine.embed(text: "again")
        #expect(
            lifecycle.isEmbedderAvailable,
            "cached-hit fast path must re-mark the swept-but-resident slot loaded"
        )
    }

    // MARK: existing call sites unaffected by nil-default lifecycle param

    @Test("engine with nil lifecycle (default) still embeds correctly")
    func nilLifecycleDefaultEmbeds() async throws {
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-lc-\(#function)"),
            loader: { _ in StubEmbedder() }
        )

        let vector = try await engine.embed(text: "hello")
        #expect(vector == [0.1, 0.2, 0.3])
    }
}
