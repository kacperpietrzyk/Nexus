import Foundation
import Hub
import os.log

/// Errors surfaced by the live HuggingFace fetcher when a download completes the
/// transfer but does not yield a loadable model.
public enum ModelDownloadError: Error, LocalizedError {
    case noWeightsLanded(hfPath: String)

    public var errorDescription: String? {
        switch self {
        case .noWeightsLanded(let hfPath):
            return "Download finished but no model weights were found for \(hfPath). Please try again."
        }
    }
}

/// Tiny thread-safe "fire once" flag so a `@Sendable` progress closure can log
/// only its FIRST invocation without a captured mutable var.
final class FirstHitFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    /// Returns `true` exactly once (on the first call); `false` thereafter.
    func hitOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

/// Real HuggingFace fetcher backed by swift-transformers 1.3.3 `Hub`.
///
/// Wraps `HubApi.snapshot(from:revision:matching:progressHandler:)`
/// (`swift-transformers/Sources/Hub/HubApi.swift`). As of 1.2.0 the legacy
/// `Hub/Downloader.swift` was removed and the transfer now runs through
/// swift-huggingface's `HubClient.downloadFile`, with per-file `.metadata`
/// sidecars and `Progress` tracking. `snapshot` resumes at *file* granularity,
/// not within a file: a fully-downloaded file whose `.metadata` commit hash
/// still matches is skipped on the next call, but an interrupted file is
/// re-downloaded from scratch (its `.incomplete` blob is discarded before each
/// attempt and `.metadata` is only written after the file completes). The
/// `startingAtByte` offset is therefore informational only — we do not drive
/// per-file resume.
///
/// `HubApi` lands a snapshot at `<downloadBase>/models/<hfPath>`
/// (`HubApi.localRepoLocation`). We point `downloadBase` at a cache folder next
/// to the model store, then **move** the snapshot contents into the manager's
/// per-manifest `destination` folder (a flat directory of safetensors + config
/// + tokenizer the Task 10/13 loaders expect) and reclaim the cache repo — see
/// ``replaceContents(of:with:)`` for why move (not copy) matters on mobile.
///
/// HubApi's own progress is file-count weighted, which barely moves while one
/// multi-GB file downloads, so progress is instead driven from the real on-disk
/// size of the cache repo (``directorySize(at:)``).
///
/// Not used by the unit tests (they inject a stub) — exercised by the
/// `INTEGRATION=1` smokes and production.
public struct LiveHFFetcher: ModelFileFetching {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus", category: "ai.modeldownload")

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

    // NOTE: do NOT enable swift-transformers' `useBackgroundSession` here.
    //
    // The intent was to survive iOS app suspension during a multi-GB transfer
    // (a foreground URLSession is torn down when the app is suspended). But
    // swift-transformers 1.3.3's background path routes the fetch through
    // `URLSession.data(for:)`, and iOS forbids data tasks on a background
    // `URLSessionConfiguration.background` session — it throws an uncaught
    // NSException (`-[__NSURLBackgroundSession _dataTaskWithTaskForClass:]`)
    // that aborts the app the instant a download starts (SIGABRT at 0%,
    // confirmed on a build-11 TestFlight crash report). Background downloads
    // therefore require a custom `URLSessionDownloadDelegate` (download tasks
    // only) rather than this flag; until that exists we use the foreground
    // session, which downloads reliably as long as the app stays in the
    // foreground. See the matching follow-up note in the PR.

    public func fetch(
        hfPath: String,
        toFile destination: URL,
        startingAtByte byteOffset: Int64,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        _ = byteOffset  // Resume is handled internally by Hub's per-file sidecars.

        Self.logger.info("LiveHFFetcher.fetch START hf=\(hfPath, privacy: .public)")
        let cacheBase = destination.deletingLastPathComponent().appending(path: ".hf-cache")
        try FileManager.default.createDirectory(
            at: cacheBase, withIntermediateDirectories: true)

        let firstSnapshotHit = FirstHitFlag()
        let hub = HubApi(downloadBase: cacheBase)
        Self.logger.info("LiveHFFetcher calling hub.snapshot hf=\(hfPath, privacy: .public)")

        // Byte-accurate progress. HubApi reports progress weighted by file
        // COUNT, so for a model dominated by ONE multi-GB `*.safetensors` the
        // parent fraction barely moves while that single file downloads — on a
        // slow link (an iPhone over wifi/cellular) the bar reads as "stuck near
        // 0%" for many minutes even though bytes are flowing, which is exactly
        // the "download hangs" report this fixes. Instead of the file-count
        // fraction, drive progress from the REAL bytes on disk: swift-huggingface
        // streams each file to a `CFNetworkDownload_*.tmp` in the process temp
        // dir, then moves the completed file into the Hub cache repo — so summing
        // the in-flight temp blob plus the cache repo tracks actual bytes
        // throughout (the temp blob grows during transfer; once it lands in the
        // repo the temp drains and the repo size takes over).
        let pollDir = cacheBase.appending(path: "models").appending(path: hfPath)
        let tempDir = FileManager.default.temporaryDirectory
        let progressPoller = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let bytes =
                    Self.directorySize(at: pollDir) + Self.inFlightDownloadBytes(in: tempDir)
                if bytes > 0 {
                    onProgress(totalBytes > 0 ? min(bytes, totalBytes) : bytes)
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }

        let snapshotURL: URL
        do {
            snapshotURL = try await hub.snapshot(
                from: Hub.Repo(id: hfPath),
                revision: "main",
                matching: Self.modelGlobs,
                progressHandler: { progress in
                    if firstSnapshotHit.hitOnce() {
                        Self.logger.info(
                            "hub.snapshot first progress callback frac=\(progress.fractionCompleted)"
                        )
                    }
                }
            )
        } catch {
            // Stop the poller before propagating so it cannot outlive the fetch
            // and report bytes for an aborted transfer.
            progressPoller.cancel()
            throw error
        }
        // Stop byte-polling BEFORE staging: the move empties the cache repo, so a
        // still-running poller would read a shrinking directory and regress the
        // bar. (Cancelling again in any later path is harmless.)
        progressPoller.cancel()

        // swift-transformers 1.3.3 `snapshot` returns a *partial* tree normally
        // (no throw) when cancelled between files — it only checks
        // `Task.isCancelled` after each file and early-returns. Bail before we
        // copy that partial snapshot or run weight validation on it, so a user
        // cancel surfaces cleanly as `CancellationError` (→ `recordCancelled`)
        // rather than as a coincidental `noWeightsLanded` error.
        try Task.checkCancellation()

        // All bytes are on disk; flip the UI to an indeterminate "Finalizing…"
        // (the negative sentinel → `ModelDownloadProgress.markFinalizing()`) so
        // the brief staging move never reads as a frozen percent.
        onProgress(-1)
        Self.logger.info("hub.snapshot RETURNED for hf=\(hfPath, privacy: .public); staging weights")
        try Self.replaceContents(of: destination, with: snapshotURL)
        // A snapshot can "succeed" without landing usable weights — an empty or
        // partial repo, or a match glob that pulled only sidecars. Marking such
        // a folder `.downloaded` leaves a model that fails to load later, so
        // require the weights to actually be present before returning.
        try Self.validateWeightsLanded(in: destination, hfPath: hfPath)
        onProgress(totalBytes)
    }

    /// Throws `ModelDownloadError.noWeightsLanded` unless `folder` contains at
    /// least one non-empty `*.safetensors` weight file. Catalog models (Qwen /
    /// Gemma / e5) all ship safetensors weights, so their absence means the
    /// snapshot did not materialize a loadable model.
    static func validateWeightsLanded(in folder: URL, hfPath: String) throws {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        let hasWeights = entries.contains { url in
            guard url.pathExtension == "safetensors" else { return false }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
        guard hasWeights else {
            throw ModelDownloadError.noWeightsLanded(hfPath: hfPath)
        }
    }

    /// Moves every entry from `source` into `destination`, replacing the
    /// destination folder so a partially-populated prior attempt cannot leave
    /// stale files behind, then deletes the now-redundant Hub cache repo to
    /// reclaim its bytes.
    ///
    /// **Move, not copy.** `source` is Hub's cache repo at
    /// `<modelsRoot>/.hf-cache/models/<hfPath>` — on the SAME volume as
    /// `destination`, so a move is an instant rename and never doubles on-disk
    /// usage. The previous copy-based staging kept the completed multi-GB
    /// weights in BOTH `.hf-cache` and the model folder (~2x on-disk, ~10 GB for
    /// a 5 GB model) and, on a storage-constrained iPhone, that transient
    /// duplicate could stall/fail the materialization with no surfaced error
    /// (the "download hangs near the end" report). The trade-off is losing Hub's
    /// revalidation fast-path: a later re-download of the same model re-fetches
    /// from scratch instead of re-hashing a cached copy. On mobile, halved disk
    /// + instant staging is worth that. `.cache` (Hub's hidden sidecar tree) is
    /// excluded from the move and then removed with the rest of the source repo.
    static func replaceContents(of destination: URL, with source: URL) throws {
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
            do {
                try fileManager.moveItem(at: entry, to: target)
            } catch {
                // Cross-volume or other move failure: fall back to a copy so the
                // model still materializes (at the old ~2x transient cost).
                try fileManager.copyItem(at: entry, to: target)
            }
        }
        // Reclaim the Hub cache repo (weights already moved out; only the small
        // `.cache`/`.metadata` sidecars remain). Best-effort: a failure here does
        // not invalidate a model that already staged correctly.
        try? fileManager.removeItem(at: source)
    }

    /// Sum of the in-flight `CFNetworkDownload_*.tmp` blobs in `tempDir` — the
    /// scratch files swift-huggingface's URLSession download task grows while a
    /// file transfers, before moving the finished file into the Hub cache repo.
    /// Counting them lets the progress bar climb during the transfer instead of
    /// jumping 0→100 only when the file lands in the repo. Best-effort: a
    /// concurrent unrelated download would also be counted, but the value is
    /// clamped to `totalBytes` by the caller, so the worst case is a bar that
    /// briefly reads full — never a wrong final state.
    static func inFlightDownloadBytes(in tempDir: URL) -> Int64 {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        return entries.reduce(into: Int64(0)) { sum, url in
            guard url.lastPathComponent.hasPrefix("CFNetworkDownload") else { return }
            sum += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// Total on-disk byte size of all regular files under `url` (recursive).
    /// Together with ``inFlightDownloadBytes(in:)`` drives byte-accurate download
    /// progress (HubApi's own progress is file-count weighted and barely moves
    /// while one multi-GB file downloads). Returns 0 when the directory does not
    /// exist yet.
    static func directorySize(at url: URL) -> Int64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: []
            )
        else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}
