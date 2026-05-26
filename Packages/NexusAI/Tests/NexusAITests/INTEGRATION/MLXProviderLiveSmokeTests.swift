import Foundation
import Testing

@testable import NexusAI

/// Live, opt-in smoke proving `MLXProvider` can load a *real* tiny on-device
/// model and produce non-empty text end-to-end.
///
/// ## Why this is `.enabled(if:)`-gated, not always-on
///
/// Loading a real model means a network download (first run) plus an on-device
/// MLX inference pass — far too slow and too offline-fragile for `swift test`
/// / CI. The whole suite is gated on `INTEGRATION=1`, matching the existing
/// repo convention (`EventKitCalendarProviderIntegrationTests`). Without the
/// env var the suite is never instantiated, so the Task 29 acceptance gate
/// (`swift test` with NO `INTEGRATION=1`) sees it as a true zero-cost no-op:
/// zero test time, zero failures. A defensive in-body guard is kept as
/// belt-and-suspenders.
///
/// ## Download API
///
/// Reuses the project's own production fetcher `LiveHFFetcher`, which wraps
/// swift-transformers' `HubApi.snapshot(from:revision:matching:progressHandler:)`
/// (`Packages/NexusAI/Sources/NexusAI/Download/ModelDownloadManager.swift:396`).
/// `LiveHFFetcher` lands a *flat* model directory (safetensors + config +
/// tokenizer) — exactly the on-disk layout `MLXChatEngine(folder:)` →
/// `loadModelContainer(from:using:)` expects. The swift-transformers Hub
/// snapshot API was re-confirmed via context7 (`/huggingface/swift-transformers`).
/// We deliberately do NOT call `Hub`/`HubApi` directly: the engine's live
/// loader is local-folder only, so weights must be staged on disk first, and
/// `LiveHFFetcher` is the canonical, production-tested staging path.
///
/// ## Model
///
/// `mlx-community/Qwen2.5-0.5B-Instruct-4bit` (~270 MB). This is the family
/// swift-transformers' own README uses for its download example; the plan's
/// suggested `Qwen3-0.5B-Instruct-4bit` does not exist on the Hub (verified
/// 401), so it was substituted per the explicit "equally-tiny known-good
/// mlx-community 4-bit chat model" authorization. The MLX live loader detects
/// architecture from `config.json`, so no family-specific wiring is needed.
///
/// ## Two-phase failure safety (mandatory)
///
/// The body is split so an environmental failure soft-skips while a genuine
/// Nexus regression hard-fails — a single broad catch would hide the latter
/// as the former, giving the pre-merge runner a false green:
///
/// - **Phase 1 (staging) — soft-skip:** directory creation + `LiveHFFetcher`
///   download, wrapped in a `do/catch` whose catch is `print` + early
///   `return` (never `Issue.record`, never a thrown error). No network,
///   HF rate-limit/404, or a stale repo id ⇒ green skip even under
///   `INTEGRATION=1`.
/// - **Phase 2 (load + generate) — hard-fail:** `MLXChatEngine`/`MLXProvider`
///   construction + `generate`, NOT wrapped in the soft-skip catch. Weights
///   are staged by now, so a throw here (loader architecture mismatch,
///   broken provider wiring, generation crash) is a real regression: `try
///   await` propagates out of this `async throws` test body as a Swift
///   Testing failure. The only non-throw failure is the model loading AND
///   generating yet returning empty text.
@Suite(
    "MLXProviderLiveSmoke (INTEGRATION=1)",
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct MLXProviderLiveSmokeTests {
    /// Tiny real chat model the live MLX loader can run. Verified to exist on
    /// the HuggingFace Hub (HTTP 200) at authoring time.
    private static let modelHFPath = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    /// Stable per-user cache so a second run reuses the already-staged weights
    /// instead of re-fetching. Survives across `swift test` invocations.
    private static func cacheFolder() -> URL {
        let base =
            FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return
            base
            .appending(path: "NexusTestModels")
            .appending(path: modelHFPath.replacingOccurrences(of: "/", with: "__"))
    }

    /// Phase-1 environmental staging (directory + weight download), shared by
    /// every smoke. Returns `true` when the model dir is staged and ready to
    /// load, `false` on an environmental staging failure (no network / HF
    /// unreachable / stale repo id) — the caller then early-returns a green
    /// soft-skip. Never throws and never `Issue.record`s: a Nexus regression
    /// surfaces only in the caller's Phase-2 load/generate path.
    private static func stageWeightsIfNeeded(at folder: URL) async -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)
            let alreadyStaged = FileManager.default.fileExists(
                atPath: folder.appending(path: "config.json").path)
            if !alreadyStaged {
                try await LiveHFFetcher().fetch(
                    hfPath: modelHFPath,
                    toFile: folder,
                    startingAtByte: 0,
                    totalBytes: 1,
                    onProgress: { _ in }
                )
            }
            return true
        } catch {
            print(
                """
                [MLXProviderLiveSmoke] soft-skipped (staging failed — expected \
                when offline or the HuggingFace Hub is unreachable): \(error)
                """
            )
            return false
        }
    }

    @Test("Loads a tiny real MLX model and generates non-empty text")
    func generatesNonEmptyText() async throws {
        // Belt-and-suspenders: the `.enabled(if:)` gate already prevents this
        // suite from being instantiated without INTEGRATION=1, but guard the
        // body too so a future refactor of the suite trait can never turn this
        // into an accidental always-on download.
        guard ProcessInfo.processInfo.environment["INTEGRATION"] == "1" else { return }

        let folder = Self.cacheFolder()

        // ── Phase 1: environmental staging — SOFT-SKIP on failure ──────────
        //
        // Directory creation + weight download (shared `stageWeightsIfNeeded`).
        // These fail for environmental reasons (no network, HF
        // unreachable/rate-limited, stale repo id), NOT because of a Nexus
        // regression — so a `false` return is a soft-skip (`print` + early
        // `return`, never `Issue.record`, never a thrown error), keeping an
        // `INTEGRATION=1` run on a flaky network green. The helper reuses
        // already-staged weights (a fully-staged dir has `config.json` at its
        // root) so a second run is an instant load. This deliberately does NOT
        // wrap Phase 2.
        guard await Self.stageWeightsIfNeeded(at: folder) else { return }

        // ── Phase 2: model load + generate — HARD-FAIL on failure ──────────
        //
        // Weights are staged on disk at this point. A throw from
        // `MLXChatEngine`/`MLXProvider` here is NOT environmental — it is a
        // genuine Nexus regression (loader architecture mismatch, broken
        // provider wiring, generation crash) that the pre-merge `INTEGRATION=1`
        // runner MUST see as a real failure, not a false-green "offline skip".
        // No catch: `try await` propagates straight out of this `async throws`
        // test body and Swift Testing reports it as a failure.
        //
        // `MLXChatEngine(folder:)` uses the LIVE loader by default
        // (`LiveMLXChatContainer.load` → `loadModelContainer(from:using:)`),
        // which loads the staged local folder. `availabilityProbe: { true }`
        // — platform availability is irrelevant under an opt-in smoke that
        // only runs on a developer's Apple-silicon Mac.
        let engine = MLXChatEngine(folder: folder)
        let provider = MLXProvider(engine: engine, availabilityProbe: { true })

        // `connectivity` defaults to `.offlineOnly`, correct for a local
        // provider. `AIRequest` has no sampling-options field — max-tokens
        // is an engine-params concern, not part of this contract.
        let response = try await provider.generate(
            AIRequest(prompt: "Say hello in Polish.", capability: .generate)
        )

        #expect(
            !response.text.isEmpty,
            "Live MLX model loaded but produced empty text."
        )
        #expect(response.providerUsed == .mlx)
    }

    /// End-to-end proof that the launch-time `AIRouter.preloadMLXChat()` entry
    /// point breaks the availability/load deadlock with REAL weights: a router
    /// wired exactly like production (MLX provider with a lifecycle-backed
    /// availability probe + a cloud fall-through) must route `.generate` to
    /// `.mlx` ONLY after `preloadMLXChat()`. Before preload the cycle is closed
    /// and the router falls through to cloud; after preload it picks MLX.
    @Test("AIRouter.preloadMLXChat() makes a real model routable end-to-end")
    func routerPreloadBreaksTheCycleWithRealWeights() async throws {
        guard ProcessInfo.processInfo.environment["INTEGRATION"] == "1" else { return }

        let folder = Self.cacheFolder()

        // ── Phase 1: environmental staging — SOFT-SKIP on failure ──────────
        guard await Self.stageWeightsIfNeeded(at: folder) else { return }

        // ── Phase 2: router wiring + cycle proof — HARD-FAIL on failure ────
        //
        // A bare lifecycle controller (no idle sweep) whose chatFolderURL()
        // resolves to the staged weights via a one-off store + a custom
        // folderProvider. The provider's availability probe reads the
        // lifecycle slot exactly as production does.
        let suite = "MLXRouterCycleSmoke"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let lifecycle = MLXLifecycleController(
            modelsRoot: folder.deletingLastPathComponent(),
            localStateStore: ModelManifestLocalState.Store(defaults: defaults),
            startSweep: false
        )
        let engine = MLXChatEngine(folderProvider: { folder }, lifecycle: lifecycle)
        let mlxChat = MLXProvider(
            engine: engine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isChatAvailable ?? false }
        )
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
            prompt: "Say hello in Polish.",
            capability: .generate,
            connectivity: .cloudAllowed
        )

        let before = try await router.route(request)
        #expect(
            before.providerUsed != .mlx,
            "pre-preload the MLX cycle must still be closed (cloud fallthrough)"
        )

        try await router.preloadMLXChat()

        let after = try await router.route(request)
        #expect(
            after.providerUsed == .mlx,
            "post-preload the router MUST route to the real MLX model — deadlock broken"
        )
        #expect(!after.text.isEmpty, "Real MLX model produced empty text post-preload.")
    }
}
