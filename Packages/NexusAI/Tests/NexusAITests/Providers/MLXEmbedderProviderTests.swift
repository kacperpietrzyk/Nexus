import Foundation
import Testing

@testable import NexusAI

// MARK: - Test doubles

/// Canned `MLXEmbedderGenerating`. Trivial + immutable; `@unchecked Sendable` is
/// test-only and safe (no mutable state crosses isolation).
private final class StubMLXEmbedder: MLXEmbedderGenerating, @unchecked Sendable {
    let cannedVector: [Float]

    init(cannedVector: [Float]) {
        self.cannedVector = cannedVector
    }

    func embed(text: String) async throws -> [Float] { cannedVector }
    func unload() async {}
}

/// Counts loader-closure invocations across calls without a data race (the loader
/// is `@Sendable` and runs off the test actor).
private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
    /// Increment and return the new count (lets a loader branch on which
    /// invocation it is).
    func bump() -> Int {
        count += 1
        return count
    }
}

/// `MLXEmbedderGenerating` that records `unload()` calls into a `LoadCounter`,
/// used to prove an orphaned mid-unload container is actually torn down.
private final class UnloadTrackingStub: MLXEmbedderGenerating, @unchecked Sendable {
    let cannedVector: [Float]
    let onUnload: LoadCounter

    init(cannedVector: [Float], onUnload: LoadCounter) {
        self.cannedVector = cannedVector
        self.onUnload = onUnload
    }

    func embed(text: String) async throws -> [Float] { cannedVector }
    func unload() async { await onUnload.increment() }
}

/// Deterministic one-shot gate. The loader `park()`s until the test calls
/// `release()`; if `release()` already ran the wait returns immediately. No
/// sleeps — the wait/signal handshake is exact.
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

// MARK: - Tests

@Test
func embedderProviderReturnsVectorOnEmbeddingVector() async throws {
    let stub = StubMLXEmbedder(cannedVector: [0.1, 0.2, 0.3, 0.4])
    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in stub }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })

    let request = AIRequest(
        prompt: "Tasks for today",
        capability: .embed,
        context: ["task-1", "task-2"]
    )
    let response = try await provider.embed(request)

    #expect(response.embeddingVector == [0.1, 0.2, 0.3, 0.4])
    #expect(response.embeddingVector?.count == 4)
    #expect(response.providerUsed == .mlx)
    #expect(response.text.isEmpty)
    #expect(response.citations == ["task-1", "task-2"])
    #expect(response.costEstimateUSD == 0)
    #expect(response.tokensUsed == .zero)
}

@Test
func embedderProviderReportsUnavailableWhenProbeIsFalse() async {
    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in StubMLXEmbedder(cannedVector: [0]) }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { false })

    #expect(provider.isAvailableOnThisPlatform == false)
    #expect(provider.capabilities == [.embed])
    #expect(provider.sendsDataExternally == false)
    #expect(provider.requiresNetwork == false)
    #expect(provider.supportsImageAttachments == false)
}

@Test
func embedderProviderRejectsGenerateAndTranscribe() async {
    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in StubMLXEmbedder(cannedVector: [0]) }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })
    let request = AIRequest(prompt: "x", capability: .generate)

    await #expect(throws: AIRouterError.providerNotImplemented(.mlx)) {
        _ = try await provider.generate(request)
    }
    await #expect(throws: AIRouterError.providerNotImplemented(.mlx)) {
        _ = try await provider.transcribe(request)
    }
}

@Test
func embedderEngineCachesContainerAcrossCalls() async throws {
    let counter = LoadCounter()
    let stub = StubMLXEmbedder(cannedVector: [1, 2, 3])
    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in
            await counter.increment()
            return stub
        }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })
    let request = AIRequest(prompt: "first", capability: .embed)

    _ = try await provider.embed(request)
    _ = try await provider.embed(request)

    #expect(await counter.count == 1)
}

@Test
func embedderEngineSingleFlightsConcurrentFirstLoads() async throws {
    let counter = LoadCounter()
    let stub = StubMLXEmbedder(cannedVector: [4, 5, 6])
    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in
            // The `await` here is the actor hop that, without single-flight,
            // lets a second concurrent first-`embed` slip past the cache check
            // and load again. With the cached-`Task` fix the closure runs once.
            await counter.increment()
            return stub
        }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })
    let request = AIRequest(prompt: "concurrent", capability: .embed)

    async let first = provider.embed(request)
    async let second = provider.embed(request)
    _ = try await (first, second)

    #expect(await counter.count == 1)
}

@Test
func embedderEngineHonorsUnloadRacingInFlightLoad() async throws {
    let counter = LoadCounter()
    let gate = LoadGate()
    let orphanUnloaded = LoadCounter()

    // The container produced by the GATED (mid-unload) load. Its `unload()`
    // bumps `orphanUnloaded`, proving `loadIfNeeded` honored the superseding
    // `unload()` instead of caching it.
    let gatedStub = UnloadTrackingStub(cannedVector: [7, 8], onUnload: orphanUnloaded)

    let engine = MLXEmbedderEngine(
        folder: URL(fileURLWithPath: "/tmp/nexus-embed"),
        loader: { _ in
            let n = await counter.bump()
            if n == 1 {
                // First (gated) load: park so the test can run `unload()` while
                // this load is suspended, then resume it.
                await gate.park()
                return gatedStub
            }
            // Any later load is a fresh post-unload reload.
            return StubMLXEmbedder(cannedVector: [9])
        }
    )
    let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })
    let request = AIRequest(prompt: "gated", capability: .embed)

    // Start the first embed; its loader parks on the gate.
    async let parked: AIResponse = provider.embed(request)
    // Deterministically wait until the loader has actually entered (count == 1)
    // so `unload()` provably races a truly in-flight load — no sleeps.
    while await counter.count < 1 { await Task.yield() }

    // unload() runs on the actor while the first load is suspended at the gate.
    await engine.unload()
    // Release the parked loader; its result must NOT be cached (superseded).
    await gate.release()
    let firstVector = try await parked.embeddingVector
    // Caller A still gets the embedding it requested.
    #expect(firstVector == [7, 8])

    // No resurrection: a follow-up embed forces a brand-new load (count -> 2)
    // because the mid-unload result was discarded, not cached.
    _ = try await provider.embed(request)
    #expect(await counter.count == 2)
    // The orphaned mid-unload container was unloaded, not leaked/cached.
    #expect(await orphanUnloaded.count == 1)
}
