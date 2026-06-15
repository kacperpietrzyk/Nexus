import Foundation

/// Current readiness state of the on-device assistant.
public enum AssistantReadiness: Sendable, Equatable {
    case notDownloaded
    case downloading(Double)  // 0...1
    case ready
    case failed(String)
}

/// Derives ``AssistantReadiness`` from local state + optional live progress.
/// `@MainActor` because it reads `ModelManifestLocalState.Store` (UserDefaults-backed,
/// but the coordinator is always used on the main actor alongside the download manager).
@MainActor
public struct AssistantReadinessResolver {
    private let store: ModelManifestLocalState.Store
    private let chatManifestID: String

    public init(localStateStore: ModelManifestLocalState.Store, chatManifestID: String) {
        self.store = localStateStore
        self.chatManifestID = chatManifestID
    }

    /// Derives the current readiness by reading local state and merging any live progress.
    public func readiness(progress: ModelDownloadProgress?) -> AssistantReadiness {
        let state = store.load(manifestID: chatManifestID)
        switch state.status {
        case .downloaded:
            return .ready
        case .downloading:
            let pct = (progress?.percent ?? state.downloadProgressPercent) / 100.0
            return .downloading(pct)
        case .error:
            return .failed(state.downloadError ?? "download failed")
        case .available:
            return .notDownloaded
        }
    }
}
