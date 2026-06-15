import Foundation

/// One-time resumable prepare coordinator: downloads any model role not yet
/// in `.downloaded` state. Idempotent — calling `prepareIfNeeded()` when both
/// roles are already downloaded is a no-op (the fetcher is never called).
///
/// `@MainActor`: drives `ModelDownloadManager` (also `@MainActor`) and is
/// typically called from the composition root on the main actor.
@MainActor
public final class AssistantPreparer {
    private let set: ResolvedModelSet
    private let downloadManager: ModelDownloadManager
    private let store: ModelManifestLocalState.Store

    public init(
        resolvedSet: ResolvedModelSet,
        downloadManager: ModelDownloadManager,
        localStateStore: ModelManifestLocalState.Store
    ) {
        self.set = resolvedSet
        self.downloadManager = downloadManager
        self.store = localStateStore
    }

    /// Downloads any role not already `.downloaded`. Auto-assignment is handled
    /// by `ModelDownloadManager` on completion via `purpose:`.
    public func prepareIfNeeded() async throws {
        if store.load(manifestID: set.chatManifestID).status != .downloaded {
            _ = try await downloadManager.startDownload(
                manifestID: set.chatManifestID,
                hfPath: set.chatHFPath,
                totalBytes: Int64(set.chatSizeGB * 1_073_741_824),
                purpose: "chat"
            )
        }
        if store.load(manifestID: set.embedderManifestID).status != .downloaded {
            _ = try await downloadManager.startDownload(
                manifestID: set.embedderManifestID,
                hfPath: set.embedderHFPath,
                totalBytes: Int64(set.embedderSizeGB * 1_073_741_824),
                purpose: "embedder"
            )
        }
    }
}
