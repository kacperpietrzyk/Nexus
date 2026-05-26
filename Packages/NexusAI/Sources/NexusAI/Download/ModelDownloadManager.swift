import Foundation
import Hub
import os.log

#if os(iOS) || os(tvOS)
import BackgroundTasks
#endif

/// Fetches the bytes of one model from a remote source into a local folder.
///
/// - Important: Despite the `toFile destination:` label, `destination` is the
///   **per-manifest model folder** (e.g. `<modelsRoot>/<manifestID>/`), not a
///   single file. ``ModelDownloadManager`` always passes a directory URL here.
///   A stub fetcher may write a single placeholder file inside it;
///   ``LiveHFFetcher`` lands a multi-file HuggingFace snapshot (safetensors +
///   config + tokenizer) inside the same folder so the Task 10/13 loaders see
///   a ready-to-load model directory.
///
/// - Important: `byteOffset` is the byte the manager *wants* to resume from.
///   ``LiveHFFetcher`` cannot honour an externally-specified byte offset across
///   a multi-file snapshot — swift-transformers' `Hub` keeps its own per-file
///   `.metadata`-sidecar resume state and resumes automatically. The offset is
///   therefore informational for the live path and authoritative only for
///   in-memory stub fetchers used in tests.
public protocol ModelFileFetching: Sendable {
    func fetch(
        hfPath: String,
        toFile destination: URL,
        startingAtByte byteOffset: Int64,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

/// Coordinates per-manifest model downloads.
///
/// Implemented as a `@MainActor final class` (not a Swift `actor`) for the same
/// reason as ``NotificationScheduler`` in Phase 1e: it drives the
/// `@MainActor @Observable` ``ModelDownloadProgress`` and is called from
/// `@MainActor` UI/test contexts, so MainActor isolation removes every hop while
/// the actual byte transfer runs off the main thread inside a detached task.
@MainActor
public final class ModelDownloadManager {
    private let localStateStore: ModelManifestLocalState.Store
    private let modelsRoot: URL
    private let fetcher: any ModelFileFetching
    private var inflight: [String: Task<Void, Never>] = [:]
    /// The live progress object for each in-flight manifest, so a repeat
    /// `startDownload` for the same ID is idempotent (returns the SAME
    /// observable) instead of spawning a second racing worker.
    private var inflightProgress: [String: ModelDownloadProgress] = [:]

    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus", category: "ai.modeldownload")

    /// Invoked AFTER `autoAssignIfNeeded` actually writes a new chat
    /// assignment (never on the no-op guard path), so the running AI graph can
    /// rebind its chat engine in-process to the just-assigned model. Optional:
    /// short-lived processes (Share extension, Meetings helper) that have no
    /// MLX graph leave it `nil`.
    private let onChatAssigned: (@MainActor @Sendable () async -> Void)?
    /// Embedder analogue of `onChatAssigned`.
    private let onEmbedderAssigned: (@MainActor @Sendable () async -> Void)?

    public init(
        localStateStore: ModelManifestLocalState.Store,
        modelsRoot: URL,
        fetcher: any ModelFileFetching,
        onChatAssigned: (@MainActor @Sendable () async -> Void)? = nil,
        onEmbedderAssigned: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        self.localStateStore = localStateStore
        self.modelsRoot = modelsRoot
        self.fetcher = fetcher
        self.onChatAssigned = onChatAssigned
        self.onEmbedderAssigned = onEmbedderAssigned
    }

    /// The `BGTaskSchedulerPermittedIdentifiers` entry registered for
    /// background model downloads. Declared `nonisolated` so it compiles on
    /// macOS (where `BGTaskScheduler` is unavailable) and is reachable from
    /// non-`@MainActor` contexts such as the unit test.
    public nonisolated static let backgroundTaskIdentifier =
        "com.kacperpietrzyk.nexus.modelDownload"

    /// Application Support / "Nexus" / "Models" — the production model store.
    ///
    /// Declared `nonisolated` (mirroring ``backgroundTaskIdentifier`` above):
    /// it is pure file-path computation with no actor-isolated state, so it
    /// stays reachable from non-`@MainActor` composition factories
    /// (`AIComposition.makeGraph`) and unit tests.
    public nonisolated static func defaultModelsRoot() -> URL {
        let base =
            FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Nexus").appending(path: "Models")
    }

    #if os(iOS) || os(tvOS)
    /// Registers the BGTask handler for model downloads. Must be called before
    /// `applicationDidFinishLaunching` returns (i.e. from `NexusiOSApp.init`
    /// via `registerBackgroundTasks`). The `notify` closure is invoked by iOS
    /// when it schedules the task; since downloads are managed by the running
    /// `URLSession`, waking the process is enough to let them continue.
    @MainActor
    public static func registerBackgroundHandler(notify: @escaping @Sendable () -> Void) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            // TODO(Phase1l later): hold `task` open while the LiveHFFetcher transfer
            // completes once a background URLSession configuration is wired. LiveHFFetcher
            // currently uses a foreground HubApi/URLSession, so waking the process and
            // completing immediately does not extend a suspended-app download window;
            // it only helps an already-in-progress foreground transfer.
            Task {
                notify()
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// Submits a `BGProcessingTaskRequest` so iOS can resume model downloads
    /// when the app is backgrounded. Call this after starting a download that
    /// may run longer than the foreground session. Safe to call multiple times;
    /// a duplicate submit merely updates the earliest-begin date.
    @MainActor
    public static func requestBackgroundCompletion(earliestBeginDate: Date = .now) {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = earliestBeginDate
        let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "ai.modeldownload")
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error(
                "BGProcessingTaskRequest submit failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
    #endif

    /// Begins (or resumes) a download for `manifestID` and returns the live
    /// ``ModelDownloadProgress`` immediately — the byte transfer runs in a
    /// detached task so callers can observe progress without blocking.
    /// - Parameter purpose: the manifest's catalog purpose
    ///   (`"chat"` / `"embedder"`, mirroring `ModelManifest.purpose`). On
    ///   successful completion, if NO model is currently assigned for that
    ///   purpose, the just-downloaded model is auto-assigned so the on-device
    ///   path is reachable end-to-end with zero manual steps (Task 27b).
    ///   The default is the deliberate no-op sentinel ``noAutoAssignPurpose``
    ///   (empty string): omitting `purpose:` performs NO auto-assignment, so a
    ///   future caller that forgets the argument can never silently make its
    ///   download the active chat model. `autoAssignIfNeeded`'s `switch` maps
    ///   any unrecognised value (including this sentinel) to `default: break`.
    ///   Production callers MUST pass an explicit `"chat"` / `"embedder"`
    ///   (both already do: `ManageModelsSection` → `manifest.purpose`,
    ///   `WelcomeMLXDownloadCoordinator` → `request.purpose`).
    @discardableResult
    public func startDownload(
        manifestID: String,
        hfPath: String,
        totalBytes: Int64,
        resumeFromBytes: Int64 = 0,
        purpose: String = ModelDownloadManager.noAutoAssignPurpose
    ) async throws -> ModelDownloadProgress {
        // Idempotent: a repeat call while a download for this manifestID is
        // already running returns the SAME live progress object instead of
        // starting a second racing worker. This eliminates both the data
        // race (two detached workers writing the same destinationFolder +
        // UserDefaults keys) and the orphaned-uncancellable-task bug (the
        // second `inflight[id] = task` overwriting the first without
        // cancelling it, so whoever finishes first nils the survivor's
        // registry entry).
        if let existing = inflightProgress[manifestID] {
            return existing
        }

        let progress = ModelDownloadProgress(manifestID: manifestID, totalBytes: totalBytes)
        let storeRoot = modelsRoot
        let destinationFolder = storeRoot.appending(path: manifestID)

        var startState = localStateStore.load(manifestID: manifestID)
        startState.status = .downloading
        startState.downloadError = nil
        localStateStore.save(manifestID: manifestID, state: startState)

        let job = DownloadJob(
            manifestID: manifestID, hfPath: hfPath, totalBytes: totalBytes,
            resumeFromBytes: resumeFromBytes, purpose: purpose, storeRoot: storeRoot,
            destinationFolder: destinationFolder, progress: progress,
            fetcher: fetcher, store: localStateStore, logger: logger,
            onChatAssigned: onChatAssigned, onEmbedderAssigned: onEmbedderAssigned)

        let task = Task.detached(priority: .utility) { [weak self] in
            await Self.runDownload(job)
            await self?.clearInflight(manifestID: manifestID)
        }

        inflight[manifestID] = task
        inflightProgress[manifestID] = progress
        return progress
    }

    /// Immutable bundle of one download's request + collaborators, passed to
    /// the detached worker as a single `Sendable` value.
    private struct DownloadJob: Sendable {
        let manifestID: String
        let hfPath: String
        let totalBytes: Int64
        let resumeFromBytes: Int64
        let purpose: String
        let storeRoot: URL
        let destinationFolder: URL
        let progress: ModelDownloadProgress
        let fetcher: any ModelFileFetching
        let store: ModelManifestLocalState.Store
        let logger: Logger
        let onChatAssigned: (@MainActor @Sendable () async -> Void)?
        let onEmbedderAssigned: (@MainActor @Sendable () async -> Void)?
    }

    /// Runs the actual byte transfer off the main thread and reflects the
    /// outcome into ``ModelManifestLocalState`` and ``ModelDownloadProgress``.
    private static func runDownload(_ job: DownloadJob) async {
        let manifestID = job.manifestID
        let destinationFolder = job.destinationFolder
        let progress = job.progress
        let store = job.store
        let logger = job.logger
        let startedAt = Date()
        await MainActor.run { progress.markStarted(at: startedAt) }

        do {
            // Ensure the parent store exists but do NOT pre-create the
            // per-manifest path itself: the fetcher owns `destination`
            // (a stub may write a single file there; LiveHFFetcher lands
            // a directory). Clear any stale entry left by a prior aborted
            // run so the fetcher always starts from a clean slate — a
            // leftover *file* at a folder path would otherwise make a
            // later `createDirectory` throw, and vice versa.
            try FileManager.default.createDirectory(
                at: job.storeRoot, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationFolder.path) {
                try FileManager.default.removeItem(at: destinationFolder)
            }
            try await job.fetcher.fetch(
                hfPath: job.hfPath,
                toFile: destinationFolder,
                startingAtByte: job.resumeFromBytes,
                totalBytes: job.totalBytes,
                onProgress: { transferred in
                    Task { @MainActor in
                        progress.transferred(
                            bytes: transferred, at: Date(), startedAt: startedAt)
                    }
                }
            )
            try Task.checkCancellation()

            var done = store.load(manifestID: manifestID)
            done.status = .downloaded
            done.localFolderPath = destinationFolder.path
            done.downloadedAt = Date()
            done.downloadProgressPercent = 100
            done.downloadError = nil
            store.save(manifestID: manifestID, state: done)
            await Self.finalizeDownloadedModel(job: job)
            await MainActor.run { progress.markCompleted() }
        } catch is CancellationError {
            // Post-`fetch` early-return path (`Task.checkCancellation()`).
            await Self.recordCancelled(job: job)
        } catch {
            // The live HTTP phase does NOT throw `CancellationError` on
            // cancel: swift-transformers' `Downloader.cancel()` broadcasts
            // `.failed(URLError(.cancelled))` (Downloader.swift:382) which
            // `HubApi.snapshot` rethrows verbatim (HubApi.swift:595-596).
            // Classify a user cancel as cancellation (→ `.available` +
            // `markCancelled()`), never as a hard download failure.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                await Self.recordCancelled(job: job)
            } else {
                let reason = error.localizedDescription
                logger.error(
                    "Model download failed for \(manifestID, privacy: .public): \(reason, privacy: .public)"
                )
                var failed = store.load(manifestID: manifestID)
                failed.status = .error
                failed.downloadError = reason
                store.save(manifestID: manifestID, state: failed)
                await MainActor.run { progress.markFailed(reason: reason) }
            }
        }
    }

    /// Auto-assigns the just-downloaded model (when nothing is assigned for its
    /// purpose yet) and, ONLY when a NEW assignment was actually written, fires
    /// the matching in-process rebind hook so the running AI graph reloads its
    /// engine against the freshly-assigned model. The no-op guard path inside
    /// `autoAssignIfNeeded` returns `false`, so an existing user/welcome
    /// assignment never triggers a redundant reload.
    private static func finalizeDownloadedModel(job: DownloadJob) async {
        let assigned = autoAssignIfNeeded(
            manifestID: job.manifestID, purpose: job.purpose, store: job.store)
        guard assigned else { return }
        switch job.purpose {
        case "chat":
            if let hook = job.onChatAssigned { await hook() }
        case "embedder":
            if let hook = job.onEmbedderAssigned { await hook() }
        default:
            break
        }
    }

    /// The no-op `purpose` sentinel: when `startDownload` is called without an
    /// explicit `purpose:`, this value flows into `autoAssignIfNeeded`, whose
    /// `switch` maps it to `default: break` — i.e. NO auto-assignment. Keeping
    /// "omitted ⇒ no assignment" the safe default prevents a future caller
    /// that forgets the argument from silently activating its download.
    public nonisolated static let noAutoAssignPurpose = ""

    /// Makes the just-downloaded model the active one for its purpose, but
    /// ONLY when nothing is assigned for that purpose yet.
    ///
    /// The `currentChatAssignment()/currentEmbedderAssignment() == nil` guard
    /// runs BEFORE any load/set/save: this is load-bearing. `Store.save`
    /// applies mutual exclusion (setting `assignedAsChat = true` for one
    /// manifest auto-clears it on every other), so a naive load→set→save here
    /// would *clear* a pre-existing user/welcome-flow assignment. Checking the
    /// current assignment first means we never override an existing one — the
    /// auto-assign only fires for the very first downloaded model of its
    /// purpose (the common Welcome-flow path), exactly as Task 27b requires.
    /// - Returns: `true` only when a NEW assignment was written (the
    ///   load/set/save path ran); `false` on every guard-return / unrecognised
    ///   purpose. Callers use this to fire the in-process rebind hook ONLY when
    ///   the active model actually changed.
    @discardableResult
    private static func autoAssignIfNeeded(
        manifestID: String,
        purpose: String,
        store: ModelManifestLocalState.Store
    ) -> Bool {
        switch purpose {
        case "chat":
            guard store.currentChatAssignment() == nil else { return false }
            var state = store.load(manifestID: manifestID)
            state.assignedAsChat = true
            store.save(manifestID: manifestID, state: state)
            return true
        case "embedder":
            guard store.currentEmbedderAssignment() == nil else { return false }
            var state = store.load(manifestID: manifestID)
            state.assignedAsEmbedder = true
            store.save(manifestID: manifestID, state: state)
            return true
        default:
            return false
        }
    }

    /// Reflects a user/early cancel into local state + progress: status
    /// reverts to `.available` (NOT `.error`), `downloadError` cleared,
    /// `ModelDownloadProgress` moves to `.cancelled`.
    private static func recordCancelled(job: DownloadJob) async {
        job.logger.info(
            "Model download cancelled: \(job.manifestID, privacy: .public)")
        var cancelledState = job.store.load(manifestID: job.manifestID)
        cancelledState.status = .available
        cancelledState.downloadError = nil
        job.store.save(manifestID: job.manifestID, state: cancelledState)
        await MainActor.run { job.progress.markCancelled() }
    }

    /// Cancels an in-flight download, if any, for `manifestID`.
    public func cancel(manifestID: String) {
        inflight[manifestID]?.cancel()
    }

    private func clearInflight(manifestID: String) {
        inflight[manifestID] = nil
        inflightProgress[manifestID] = nil
    }

    /// Test-visible count of currently-registered in-flight downloads.
    /// Used by tests to assert no leaked/orphaned registry entries.
    var inflightCount: Int { inflight.count }
}

/// Real HuggingFace fetcher backed by swift-transformers 1.1.9 `Hub`.
///
/// Wraps `HubApi.snapshot(from:revision:matching:progressHandler:)`
/// (`swift-transformers/Sources/Hub/HubApi.swift:614`). That call already
/// performs resumable HTTP `Range` downloads with per-file `.metadata`
/// sidecars and progress tracking (`Hub/Downloader.swift:18,180,250`), so the
/// `startingAtByte` offset is informational only — `Hub` resumes any partial
/// files automatically on the next call.
///
/// `HubApi` lands a snapshot at `<downloadBase>/models/<hfPath>`
/// (`HubApi.localRepoLocation`, `HubApi.swift:378`). We point `downloadBase`
/// at a stable cache folder next to the model store so the resume sidecars
/// survive across launches, then **copy** the snapshot contents into the
/// manager's per-manifest `destination` folder so the Task 10/13 loaders see
/// a flat model directory of safetensors + config + tokenizer. Copy (not
/// move) is deliberate — see ``replaceContents(of:with:)``.
///
/// Not used by the unit tests (they inject a stub) — exercised by Task 28's
/// `INTEGRATION=1` smoke and production.
public struct LiveHFFetcher: ModelFileFetching {
    /// Globs covering MLX weights + config + tokenizer for the model families
    /// in `DefaultCatalog.json` (Qwen / Gemma safetensors, e5 embedders).
    private static let modelGlobs = [
        "*.safetensors",
        "*.json",
        "*.txt",
        "tokenizer*",
        "*.model",
    ]

    public init() {}

    public func fetch(
        hfPath: String,
        toFile destination: URL,
        startingAtByte byteOffset: Int64,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        _ = byteOffset  // Resume is handled internally by Hub's per-file sidecars.

        let cacheBase = destination.deletingLastPathComponent().appending(path: ".hf-cache")
        try FileManager.default.createDirectory(
            at: cacheBase, withIntermediateDirectories: true)

        let hub = HubApi(downloadBase: cacheBase)
        let snapshotURL = try await hub.snapshot(
            from: Hub.Repo(id: hfPath),
            revision: "main",
            matching: Self.modelGlobs,
            progressHandler: { progress in
                // HubApi weights `Progress` by file COUNT (one parent unit
                // per file, HubApi.swift:663-665), not bytes — so this byte
                // figure is a coarse approximation. It is corrected by trailing
                // `onProgress(totalBytes)` below and clamped by
                // `ModelDownloadProgress.percent` (min(100, …)).
                onProgress(Int64(progress.fractionCompleted * Double(totalBytes)))
            }
        )

        try Self.replaceContents(of: destination, with: snapshotURL)
        onProgress(totalBytes)
    }

    /// Copies every entry from `source` into `destination`, replacing the
    /// destination folder so a partially-populated prior attempt cannot leave
    /// stale files behind.
    ///
    /// **Copy, not move, is deliberate.** `source` is Hub's cache repo at
    /// `<modelsRoot>/.hf-cache/models/<hfPath>`; moving it would delete the
    /// completed weight files Hub uses for its revalidation fast-path, forcing
    /// a full redownload/re-hash on the next `snapshot`. The cost is that the
    /// completed multi-GB weights (not just `.cache`/`.metadata` sidecars)
    /// remain in `.hf-cache` — roughly ~2x on-disk per materialized model
    /// until cache eviction. `.cache` is excluded from the copy (it is Hub's
    /// internal sidecar tree, not part of the model dir).
    private static func replaceContents(of destination: URL, with source: URL) throws {
        // TODO(Phase1l+): .hf-cache eviction once a model is materialized to
        // reclaim the ~2x duplicate weight bytes.
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let entries = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for entry in entries where entry.lastPathComponent != ".cache" {
            let target = destination.appending(path: entry.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: entry, to: target)
        }
    }
}
