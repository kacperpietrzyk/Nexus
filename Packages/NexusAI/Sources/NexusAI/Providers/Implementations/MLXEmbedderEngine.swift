import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon

// MARK: - Public protocol surface

/// Abstraction over an on-device embedding generator. The unit tests substitute a
/// stub; production uses `LiveMLXEmbedderContainer` backed by `MLXEmbedders`.
///
/// Embeddings use the SEPARATE `MLXEmbedders` module, NOT the LLM `ModelContainer`
/// / `generate` path. `embed(text:)` returns one L2-normalized vector for a single
/// string (batch of 1).
public protocol MLXEmbedderGenerating: Sendable {
    func embed(text: String) async throws -> [Float]
    func unload() async
}

// MARK: - Errors

public enum MLXEmbedderEngineError: Error, Sendable {
    /// The app is not foreground-active, so GPU work is refused (issue #51).
    /// A *catchable* Swift error raised BEFORE any Metal command buffer is
    /// submitted — the alternative is MLX's uncatchable C++ `throw` →
    /// `std::terminate` when the OS rejects a background submission.
    case backgrounded
}

// MARK: - Engine actor

/// Caches a single loaded embedder across calls, mirroring `MLXChatEngine`'s
/// load-once pattern.
///
/// There is deliberately NO busy/waiters slot here (unlike `MLXChatEngine`):
/// `EmbedderModelContainer.perform` routes through `MLXEmbedders`'
/// `SerialAccessContainer`, which already serializes every access to the
/// non-`Sendable` `EmbedderModelContext`. Concurrent `embed(text:)` calls are
/// therefore safe — the container itself is the single-flight gate.
public actor MLXEmbedderEngine {
    public typealias Loader =
        @Sendable (URL) async throws -> any MLXEmbedderGenerating

    /// Resolved lazily at every cold load so an embedder assignment that
    /// changed after `init` targets the currently-assigned folder, not the one
    /// captured at composition time.
    private let folderProvider: @Sendable () -> URL
    private let loader: Loader
    /// Strong optional — not `weak` because `MLXLifecycleController` never holds
    /// a reference back to the engine (it is state-only), so there is no retain
    /// cycle. A `weak` ref would silently drop notifications whenever the
    /// composition graph has any ownership gap, defeating the feature entirely.
    private let lifecycle: MLXLifecycleController?
    private var container: (any MLXEmbedderGenerating)?
    private var loadingTask: Task<any MLXEmbedderGenerating, Error>?
    /// Monotonic load-epoch. Bumped by `unload()` so a load that was in flight
    /// when `unload()` ran can detect on resume that it was superseded. (Swift's
    /// `Task` is a value type — `===` identity is unavailable — so the epoch is
    /// the supersession token.)
    private var loadGeneration = 0

    /// Static-folder init. Preserved verbatim as the test surface — every
    /// existing embedder test constructs the engine with a fixed `folder:` and
    /// must keep compiling unchanged.
    public init(
        folder: URL,
        lifecycle: MLXLifecycleController? = nil,
        loader: @escaping Loader = { folder in
            try await LiveMLXEmbedderContainer.load(folder: folder)
        }
    ) {
        self.init(folderProvider: { folder }, lifecycle: lifecycle, loader: loader)
    }

    /// Dynamic-folder init used by `AIComposition.makeGraph`: the folder is
    /// re-resolved at every cold load via `lifecycle.embedderFolderURL()`, so a
    /// post-launch assignment change rebinds the next load to the new model.
    public init(
        folderProvider: @escaping @Sendable () -> URL,
        lifecycle: MLXLifecycleController? = nil,
        loader: @escaping Loader = { folder in
            try await LiveMLXEmbedderContainer.load(folder: folder)
        }
    ) {
        self.folderProvider = folderProvider
        self.lifecycle = lifecycle
        self.loader = loader
    }

    public func embed(text: String) async throws -> [Float] {
        // Issue #51: refuse GPU work in the background BEFORE touching the idle
        // clock or loading weights (the load + the `perform` closure both submit
        // Metal command buffers the OS rejects when not foreground-active).
        // `nil` lifecycle (stub tests) = no gate.
        if let lifecycle, !lifecycle.isForegroundActive {
            throw MLXEmbedderEngineError.backgrounded
        }
        // Refresh the idle clock so active search/retrieval use is not swept
        // mid-operation. No-op when the slot is empty (Task-15 guard on touchEmbedder).
        lifecycle?.touchEmbedder()
        let generator = try await loadIfNeeded()
        return try await generator.embed(text: text)
    }

    /// Warms the embedder container without routing a synthetic embed request.
    /// The single-flight `loadIfNeeded` already fires `markEmbedderLoaded()` on
    /// the winning path, so a bare load is the whole warmup.
    public func preload() async throws {
        // Issue #51: gate the launch-time embedder warmup (loads weights →
        // `MLX.eval`) behind the foreground state. `nil` lifecycle = no gate.
        if let lifecycle, !lifecycle.isForegroundActive {
            throw MLXEmbedderEngineError.backgrounded
        }
        _ = try await loadIfNeeded()
    }

    public func unload() async {
        await container?.unload()
        container = nil
        // Drop any in-flight load AND bump the epoch so a load that is currently
        // suspended detects on resume that it was superseded and does not
        // resurrect cached state.
        loadingTask = nil
        loadGeneration += 1
        // Keep the lifecycle slot consistent with engine teardown (same
        // rationale as `MLXChatEngine.unload()`): a dropped container must not
        // read `.loaded`, or `reload()`'s unload→preload window lets a
        // concurrent `route` slip through onto the just-dropped model.
        lifecycle?.unloadEmbedder()
    }

    /// Single-flight load. The actor hop inside `loader(folder)` is a suspension
    /// point, so a naive `if container == nil { load }` lets two concurrent
    /// first-`embed` calls both load (the second orphaning the first — a real
    /// double-load of a >1 GB model on iPhone). Caching the in-flight `Task`
    /// collapses concurrent loads to one without reintroducing a busy/waiters
    /// gate: only the LOAD is single-flight; post-load access stays serialized by
    /// `SerialAccessContainer`. A failed load clears the task so transient loader
    /// errors remain retryable.
    ///
    /// The producer write is epoch-guarded against a concurrent `unload()`. Each
    /// load captures `loadGeneration`; `unload()` bumps it. If an `unload()` runs
    /// while this load is suspended, on resume the captured epoch is stale: the
    /// caller still receives the embedding it requested (do NOT fail it), but the
    /// engine does NOT resurrect cached state — it unloads the now-orphaned
    /// container so a successful `unload()` still means the model is freed. The
    /// symmetric `catch` guard avoids a failed, superseded load nil-ing a newer
    /// retry's slot.
    private func loadIfNeeded() async throws -> any MLXEmbedderGenerating {
        if let container {
            // Fast path re-`markEmbedderLoaded()`: after an idle sweep (or
            // memory-guard eviction) the lifecycle slot is `.empty` while
            // `container` stays non-nil. Re-marking re-promotes the still-resident
            // container so `isEmbedderAvailable` flips back true on the next
            // ungated hit (e.g. `preload()` on foreground return), instead of
            // leaving the embedder silently unavailable until model-reassign or
            // app restart. Redundant-but-harmless when already `.loaded` (it only
            // resets `idleSince`, same as the `touchEmbedder()` `embed` performs).
            lifecycle?.markEmbedderLoaded()
            return container
        }
        if let loadingTask {
            return try await loadingTask.value
        }
        let generation = loadGeneration
        let resolvedFolder = folderProvider()
        let task = Task { try await loader(resolvedFolder) }
        loadingTask = task
        do {
            let loaded = try await task.value
            if loadGeneration == generation {
                container = loaded
                loadingTask = nil
                // Notify the lifecycle controller that the embedder slot is live.
                // Placed inside the winning (non-stale) branch — the `else`
                // branch below is the epoch-rejected/orphan path where the
                // container is immediately unloaded without being cached, so
                // calling mark there would create phantom availability. (The
                // cached-hit fast path above re-marks for the swept-then-re-hit
                // case, but that path never reaches this stale `else`.)
                lifecycle?.markEmbedderLoaded()
            } else {
                // A superseding `unload()` ran mid-load: honor it.
                await loaded.unload()
            }
            return loaded
        } catch {
            if loadGeneration == generation {
                loadingTask = nil
            }
            throw error
        }
    }
}

// MARK: - Live container (real mlx-swift-lm 3.31.3 bridge)

/// Real `MLXEmbedderGenerating` backed by `MLXEmbedders.EmbedderModelContainer`.
///
/// Loaded from a local directory (the model is fetched separately by the HF
/// fetcher) via `EmbedderModelFactory.shared.loadContainer(from:using:)`, reusing
/// the hand-written `SwiftTransformersTokenizerLoader` shipped for the LLM path.
///
/// mlx-swift-lm 3.31.3 ships NO `embed(text:) -> [Float]` convenience: the
/// encode → pad → `pooling(model(...))` → materialize recipe is hand-rolled
/// inside `container.perform`. Every `MLXArray` is created, used, and evaluated
/// inside that closure; only the materialized `[Float]` escapes, because
/// `EmbedderModelContext` / `MLXArray` are NOT `Sendable`.
public struct LiveMLXEmbedderContainer: MLXEmbedderGenerating {
    private let container: EmbedderModelContainer

    public static func load(folder: URL) async throws -> any MLXEmbedderGenerating {
        let container = try await EmbedderModelFactory.shared.loadContainer(
            from: folder,
            using: SwiftTransformersTokenizerLoader()
        )
        return LiveMLXEmbedderContainer(container: container)
    }

    public func embed(text: String) async throws -> [Float] {
        // The non-deprecated `perform` form yields the whole `EmbedderModelContext`
        // (the `(EmbeddingModel, Tokenizer, Pooling)` closure overload is
        // `@available(*, deprecated)` and would warn under strict builds).
        try await container.perform { context -> [Float] in
            let tokenizer = context.tokenizer
            let eosID = tokenizer.eosTokenId ?? 0

            // Single string = batch of 1; no cross-row padding is needed, but we
            // still build the rank-2 `[1, seqLen]` tensors the model + pooling
            // expect.
            let tokens = tokenizer.encode(text: text, addSpecialTokens: true)
            let padded = stacked([MLXArray(tokens)])
            let attentionMask = padded .!= eosID
            let tokenTypeIds = MLXArray.zeros(like: padded)

            let pooled = context.pooling(
                context.model(
                    padded,
                    positionIds: nil,
                    tokenTypeIds: tokenTypeIds,
                    attentionMask: attentionMask
                ),
                normalize: true,
                applyLayerNorm: true
            )

            // Materialize INSIDE the closure — `MLXArray` is not `Sendable`, only
            // the realized `[Float]` may cross the isolation boundary. `asArray`
            // flattens the ENTIRE contiguous buffer; here `pooled` is `[1, dim]`
            // (batch == 1), so the flattened buffer equals the single `dim`-length
            // vector. This identity holds ONLY for batch-of-1 — generalizing to
            // batch > 1 would require reshaping/indexing per row first.
            MLX.eval(pooled)
            return pooled.asArray(Float.self)
        }
    }

    public func unload() async {
        // mlx-swift-lm exposes no explicit teardown; dropping the only strong
        // reference lets ARC release the container and its weights. The engine
        // nils its `container` field after this returns.
    }
}
