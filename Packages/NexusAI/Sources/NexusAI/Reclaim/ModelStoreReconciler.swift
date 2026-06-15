import Foundation

/// Disk-truth model-store reconciler: classifies every directory under the known
/// roots against the current `ResolvedModelSet`, so it can both report real sizes
/// to the UI and reclaim orphans without ever touching the actively-loaded model.
///
/// Uses `@unchecked Sendable` because `FileManager` is Apple-documented as
/// thread-safe, matching the pattern in ``ModelManifestLocalState/Store``.
public struct ModelStoreReconciler: @unchecked Sendable {
    private let roots: ModelStorageRoots
    private let store: ModelManifestLocalState.Store
    private let canonical: ResolvedModelSet
    private let whisperVariant: String
    private let fileManager: FileManager

    public init(
        roots: ModelStorageRoots,
        store: ModelManifestLocalState.Store,
        canonical: ResolvedModelSet,
        whisperVariant: String,
        fileManager: FileManager = .default
    ) {
        self.roots = roots
        self.store = store
        self.canonical = canonical
        self.whisperVariant = whisperVariant
        self.fileManager = fileManager
    }

    public func scan() -> [ModelStoreEntry] {
        var entries: [ModelStoreEntry] = []
        entries.append(contentsOf: scanManagedModels())
        entries.append(contentsOf: scanHubCache())
        entries.append(contentsOf: scanWhisper())
        if let staging = stagingEntry() { entries.append(staging) }
        return entries
    }

    // MARK: Managed store (App-Support/Nexus/Models/<id>)

    private func scanManagedModels() -> [ModelStoreEntry] {
        subdirectories(of: roots.managedModels)
            .filter { $0.lastPathComponent != ".hf-cache" }
            .map { dir in
                let id = dir.lastPathComponent
                let state = store.load(manifestID: id)
                let kind: ModelStoreEntry.Kind =
                    id == canonical.chatManifestID
                    ? .chat
                    : id == canonical.embedderManifestID ? .embedder : .unknown
                let classification = classifyManaged(id: id, state: state)
                return ModelStoreEntry(
                    id: id, path: dir, sizeBytes: directorySize(dir),
                    kind: kind, classification: classification)
            }
    }

    private func classifyManaged(
        id: String,
        state: ModelManifestLocalState
    ) -> ModelStoreEntry.Classification {
        if state.status == .downloading { return .inFlight }
        if id == canonical.chatManifestID || id == canonical.embedderManifestID {
            return .canonical
        }
        // Non-canonical managed model. Protect it only when it is the chat model the
        // app currently loads AND the new canonical chat is not yet downloaded —
        // otherwise the user would be left with no working assistant.
        let canonicalChatReady =
            store.load(manifestID: canonical.chatManifestID).status == .downloaded
        let isActiveChat = store.currentChatAssignment() == id
        if isActiveChat && !canonicalChatReady { return .staleButActive }
        return .orphan
    }

    // MARK: Default HF hub cache (always orphan — app never loads from here)

    private func scanHubCache() -> [ModelStoreEntry] {
        subdirectories(of: roots.hubCache)
            .filter { $0.lastPathComponent.hasPrefix("models--") }
            .map { dir in
                ModelStoreEntry(
                    id: dir.lastPathComponent, path: dir, sizeBytes: directorySize(dir),
                    kind: .unknown, classification: .orphan)
            }
    }

    // MARK: WhisperKit variants

    private func scanWhisper() -> [ModelStoreEntry] {
        subdirectories(of: roots.whisperKit).map { dir in
            let id = dir.lastPathComponent
            return ModelStoreEntry(
                id: id, path: dir, sizeBytes: directorySize(dir), kind: .transcription,
                classification: id == whisperVariant ? .canonical : .orphan)
        }
    }

    // MARK: Staging leftovers

    private func stagingEntry() -> ModelStoreEntry? {
        let size = directorySize(roots.stagingCache)
        guard size > 0 else { return nil }
        // Only an orphan when no download is in flight; a running LiveHFFetcher uses it.
        let anyDownloading = subdirectories(of: roots.managedModels).contains {
            store.load(manifestID: $0.lastPathComponent).status == .downloading
        }
        return ModelStoreEntry(
            id: ".hf-cache", path: roots.stagingCache, sizeBytes: size, kind: .unknown,
            classification: anyDownloading ? .inFlight : .orphan)
    }

    // MARK: Helpers

    /// Lists immediate subdirectories, including hidden ones (`.hf-cache` is dot-prefixed,
    /// so `options: []` — never `.skipsHiddenFiles`).
    private func subdirectories(of root: URL) -> [URL] {
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        LiveHFFetcher.directorySize(at: url)
    }
}
