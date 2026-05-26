import Foundation
import Synchronization
import Testing

@testable import NexusAI

// MARK: - Shared stubs

/// Trivial synchronous chat stub — never parks, never fails. Records unload.
private final class StubChat: MLXChatGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var unloadedCount = 0
    var unloadCount: Int { lock.withLock { unloadedCount } }

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

    func unload() async { lock.withLock { unloadedCount += 1 } }
}

private final class StubEmbedder: MLXEmbedderGenerating, @unchecked Sendable {
    func embed(text: String) async throws -> [Float] { [0.1, 0.2, 0.3] }
    func unload() async {}
}

/// Suspending gate to deterministically race an in-flight chat load with
/// `unload()` (mirrors `LoadGate` from the embedder integration tests).
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
    func bump() -> Int { count += 1; return count }
}

private func makeStore(_ fn: String) -> ModelManifestLocalState.Store {
    let defaults = UserDefaults(suiteName: fn)!
    defaults.removePersistentDomain(forName: fn)
    return ModelManifestLocalState.Store(defaults: defaults)
}

private func makeLifecycle(fn: String) -> MLXLifecycleController {
    MLXLifecycleController(
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-preload-\(fn)", directoryHint: .isDirectory),
        localStateStore: makeStore(fn),
        startSweep: false
    )
}

// MARK: - Engine preload / dynamic-folder / epoch tests

@Suite("MLX engine preload + dynamic folder + chat unload-race epoch")
struct MLXEnginePreloadReloadTests {

    @Test("chat preload() flips the lifecycle slot to loaded")
    func chatPreloadFlipsSlot() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }

        #expect(!lifecycle.isChatAvailable, "precondition: empty before preload")
        try await engine.preload()
        #expect(lifecycle.isChatAvailable, "preload must warm and mark the chat slot loaded")
    }

    @Test("embedder preload() flips the lifecycle slot to loaded")
    func embedderPreloadFlipsSlot() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let engine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in StubEmbedder() }
        )

        #expect(!lifecycle.isEmbedderAvailable, "precondition: empty before preload")
        try await engine.preload()
        #expect(lifecycle.isEmbedderAvailable, "preload must warm and mark the embedder slot loaded")
    }

    @Test("chat engine re-resolves the folder on every cold load (rebind)")
    func chatDynamicFolderRebinds() async throws {
        // The folderProvider returns whatever the mutable box currently holds.
        // After unload(), the next load must re-resolve — proving an assignment
        // change after construction is honored, not the captured-at-init path.
        let box = Mutex(URL(fileURLWithPath: "/models/old"))
        let seen = Mutex<[String]>([])
        let engine = MLXChatEngine(
            folderProvider: { box.withLock { $0 } },
            loader: { folder, _ in
                seen.withLock { $0.append(folder.path) }
                return StubChat()
            }
        )

        try await engine.preload()
        box.withLock { $0 = URL(fileURLWithPath: "/models/new") }
        await engine.unload()
        try await engine.preload()

        #expect(seen.withLock { $0 } == ["/models/old", "/models/new"])
    }

    @Test("embedder engine re-resolves the folder on every cold load (rebind)")
    func embedderDynamicFolderRebinds() async throws {
        let box = Mutex(URL(fileURLWithPath: "/models/e-old"))
        let seen = Mutex<[String]>([])
        let engine = MLXEmbedderEngine(
            folderProvider: { box.withLock { $0 } },
            loader: { folder in
                seen.withLock { $0.append(folder.path) }
                return StubEmbedder()
            }
        )

        try await engine.preload()
        box.withLock { $0 = URL(fileURLWithPath: "/models/e-new") }
        await engine.unload()
        try await engine.preload()

        #expect(seen.withLock { $0 } == ["/models/e-old", "/models/e-new"])
    }

    @Test("static-folder init still passes the fixed folder to the loader")
    func staticFolderInitPreserved() async throws {
        let seen = Mutex<[String]>([])
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null")
        ) { folder, _ in
            seen.withLock { $0.append(folder.path) }
            return StubChat()
        }

        try await engine.preload()
        #expect(seen.withLock { $0 } == ["/dev/null"])
    }

    // The chat engine had the SAME unload-during-load race the embedder solved
    // (loader suspends; unload() runs in that window; the resumed load must NOT
    // resurrect the model). The rebind path (unload→preload) activates it, so
    // this proof is in scope for 27c. Mirrors the embedder epoch test exactly.
    @Test(
        "chat loadGeneration epoch drops a post-await write when unload() raced",
        .timeLimit(.minutes(1))
    )
    func chatEpochRejectsStaleLoad() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let gate = LoadGate()
        let counter = LoadCounter()
        let orphan = StubChat()

        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in
            let number = await counter.bump()
            if number == 1 {
                // First (gated) load: park until the test triggers unload.
                await gate.park()
                return orphan  // stale result the engine must reject
            }
            return StubChat()
        }

        // Start preload — its loader parks at the gate (count == 1).
        async let parked: Void = engine.preload()
        while await counter.count < 1 { await Task.yield() }

        // unload() races the in-flight load, bumping loadGeneration.
        await engine.unload()

        // Release the parked loader — its result must be epoch-rejected.
        await gate.release()
        try await parked

        // KEY ASSERTION: the slot must remain EMPTY because markChatLoaded()
        // must NOT fire on the stale/epoch-rejected path (the orphan container
        // is immediately unloaded without being cached).
        #expect(
            !lifecycle.isChatAvailable,
            "markChatLoaded must NOT fire on the stale/epoch-rejected chat load path"
        )
        #expect(orphan.unloadCount == 1, "orphaned chat container must be unloaded")
    }

    @Test("engine.unload() clears the lifecycle slot (reload window safety)")
    func unloadClearsLifecycleSlot() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }

        try await engine.preload()
        #expect(lifecycle.isChatAvailable, "precondition: loaded after preload")

        await engine.unload()
        #expect(
            !lifecycle.isChatAvailable,
            "unload must clear the lifecycle slot so a stale folder cannot be routed mid-reload"
        )
    }
}

// MARK: - Provider preload / reload tests

@Suite("MLXProvider / MLXEmbedderProvider preload + reload")
struct MLXProviderPreloadReloadTests {

    @Test("MLXProvider.preload() warms the engine and flips availability")
    func providerPreloadWarms() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let engine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }
        let provider = MLXProvider(
            engine: engine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isChatAvailable ?? false }
        )

        #expect(provider.isAvailableOnThisPlatform == false)
        try await provider.preload()
        #expect(provider.isAvailableOnThisPlatform == true)
    }

    @Test("MLXProvider.reload() drops the stale container then re-warms a new folder")
    func providerReloadRebinds() async throws {
        let box = Mutex(URL(fileURLWithPath: "/models/p-old"))
        let seen = Mutex<[String]>([])
        let engine = MLXChatEngine(
            folderProvider: { box.withLock { $0 } },
            loader: { folder, _ in
                seen.withLock { $0.append(folder.path) }
                return StubChat()
            }
        )
        let provider = MLXProvider(engine: engine, availabilityProbe: { true })

        try await provider.preload()
        box.withLock { $0 = URL(fileURLWithPath: "/models/p-new") }
        try await provider.reload()

        #expect(seen.withLock { $0 } == ["/models/p-old", "/models/p-new"])
    }

    @Test("MLXEmbedderProvider.reload() drops the stale container then re-warms a new folder")
    func embedderProviderReloadRebinds() async throws {
        let box = Mutex(URL(fileURLWithPath: "/models/pe-old"))
        let seen = Mutex<[String]>([])
        let engine = MLXEmbedderEngine(
            folderProvider: { box.withLock { $0 } },
            loader: { folder in
                seen.withLock { $0.append(folder.path) }
                return StubEmbedder()
            }
        )
        let provider = MLXEmbedderProvider(engine: engine, availabilityProbe: { true })

        try await provider.preload()
        box.withLock { $0 = URL(fileURLWithPath: "/models/pe-new") }
        try await provider.reload()

        #expect(seen.withLock { $0 } == ["/models/pe-old", "/models/pe-new"])
    }
}

// MARK: - Router-level cycle-broken proof (the empirical assertion)

@Suite("AIRouter MLX preload breaks the availability/load deadlock")
struct AIRouterMLXPreloadCycleTests {

    /// This is the discriminating test the spec demands: a unit assertion that
    /// `preload()` mutates the slot proves the *engine*, not that the deadlock
    /// is gone. Here a real `MLXLifecycleController` + stub-loader
    /// `MLXChatEngine` + real `MLXProvider` are wired EXACTLY like production
    /// (`availabilityProbe: { lifecycle.isChatAvailable }`). A cloud
    /// `FakeAIProvider` (`requiresNetwork: true`) is the fall-through target.
    ///
    /// Pre-preload the cycle is closed → the router cannot select MLX and falls
    /// through to cloud. Post-`preloadMLXChat()` the router MUST select `.mlx`.
    /// If the post-preload assertion fails, the deadlock still ships.
    @Test("route(.generate) selects .mlx only AFTER preloadMLXChat()")
    func preloadBreaksTheCycle() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let chatEngine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: lifecycle
        ) { _, _ in StubChat() }
        let mlxChat = MLXProvider(
            engine: chatEngine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isChatAvailable ?? false }
        )

        // Cloud fall-through target: requiresNetwork ⇒ cloud bucket;
        // id .appleIntelligence is on-device so consent auto-grants, and the
        // default InMemoryQuotaTracker is unlimited — it passes both gates.
        let cloud = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            sendsDataExternally: true,
            requiresNetwork: true
        )

        let router = AIRouter(
            providers: [mlxChat, cloud],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        let request = AIRequest(
            prompt: "hi",
            capability: .generate,
            connectivity: .cloudAllowed
        )

        // Pre-preload: the availability/load cycle is closed — MLX cannot be
        // selected, so the router falls through to the cloud provider.
        let before = try await router.route(request)
        #expect(
            before.providerUsed != .mlx,
            "pre-preload the MLX cycle must still be closed (cloud fallthrough)"
        )

        // The cycle-break entry point.
        try await router.preloadMLXChat()

        // Post-preload: the router MUST now pick the on-device MLX provider.
        let after = try await router.route(request)
        #expect(
            after.providerUsed == .mlx,
            "post-preload the router MUST select .mlx — the deadlock is broken"
        )
    }

    @Test("preloadMLXEmbedder() makes the embedder routable for .embed")
    func embedderPreloadBreaksTheCycle() async throws {
        let lifecycle = makeLifecycle(fn: #function)
        let embedderEngine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-\(#function)"),
            lifecycle: lifecycle,
            loader: { _ in StubEmbedder() }
        )
        let mlxEmbedder = MLXEmbedderProvider(
            engine: embedderEngine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isEmbedderAvailable ?? false }
        )
        let router = AIRouter(
            providers: [mlxEmbedder],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        let request = AIRequest(prompt: "embed me", capability: .embed)

        // Pre-preload: no available embedder ⇒ selection fails.
        #expect(await router.hasAvailableProvider(for: request) == false)

        try await router.preloadMLXEmbedder()

        let response = try await router.route(request)
        #expect(response.providerUsed == .mlx)
    }

    @Test("preloadMLXChat throws when no MLXProvider is registered")
    func preloadThrowsWhenNoProvider() async throws {
        let router = AIRouter(
            providers: [FakeAIProvider(id: .appleIntelligence)],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        await #expect(throws: AIRouterError.noProviderAvailable) {
            try await router.preloadMLXChat()
        }
    }

    // Both MLXProvider and MLXEmbedderProvider have id == .mlx. An id-keyed
    // lookup would be ambiguous; the router uses concrete-type disambiguation.
    // This pins that the chat preload reaches the CHAT engine even when an
    // embedder provider is registered first in the list.
    @Test("concrete-type lookup picks the chat provider, not the embedder")
    func concreteTypeDisambiguation() async throws {
        let chatLifecycle = makeLifecycle(fn: "\(#function)-chat")
        let embedderLifecycle = makeLifecycle(fn: "\(#function)-embed")

        let chatEngine = MLXChatEngine(
            folder: URL(fileURLWithPath: "/dev/null"),
            lifecycle: chatLifecycle
        ) { _, _ in StubChat() }
        let embedderEngine = MLXEmbedderEngine(
            folder: URL(fileURLWithPath: "/tmp/nexus-embed-\(#function)"),
            lifecycle: embedderLifecycle,
            loader: { _ in StubEmbedder() }
        )

        let mlxChat = MLXProvider(
            engine: chatEngine,
            availabilityProbe: { [weak chatLifecycle] in chatLifecycle?.isChatAvailable ?? false }
        )
        let mlxEmbedder = MLXEmbedderProvider(
            engine: embedderEngine,
            availabilityProbe: { [weak embedderLifecycle] in
                embedderLifecycle?.isEmbedderAvailable ?? false
            }
        )

        // Embedder registered FIRST — an `id == .mlx` lookup would hit it.
        let router = AIRouter(
            providers: [mlxEmbedder, mlxChat],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        try await router.preloadMLXChat()

        #expect(chatLifecycle.isChatAvailable, "chat preload must warm the CHAT engine")
        #expect(
            !embedderLifecycle.isEmbedderAvailable,
            "chat preload must NOT warm the embedder engine (concrete-type lookup)"
        )
    }
}
