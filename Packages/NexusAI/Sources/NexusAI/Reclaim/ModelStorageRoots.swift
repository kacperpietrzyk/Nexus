import Foundation

/// The four on-disk roots where model bytes can accumulate. Injectable so the
/// reconciler can run against a temp tree in tests.
public struct ModelStorageRoots: Sendable {
    /// `App-Support/Nexus/Models` — the canonical managed store the app loads from.
    public let managedModels: URL
    /// `Caches/huggingface/hub` — the default HuggingFace Hub cache. The app never
    /// loads from here; any `models--…` repo under it is residue (old scheme / spike).
    public let hubCache: URL
    /// `App-Support/Nexus/WhisperKit/models/argmaxinc/whisperkit-coreml` — Whisper variants.
    public let whisperKit: URL
    /// `App-Support/Nexus/Models/.hf-cache` — LiveHFFetcher's transient staging dir.
    public let stagingCache: URL

    public init(managedModels: URL, hubCache: URL, whisperKit: URL, stagingCache: URL) {
        self.managedModels = managedModels
        self.hubCache = hubCache
        self.whisperKit = whisperKit
        self.stagingCache = stagingCache
    }

    /// The real roots on this device.
    public static func production() -> ModelStorageRoots {
        let models = ModelDownloadManager.defaultModelsRoot()
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let whisperBase =
            WhisperKitProvider.defaultDownloadBase()
            ?? models.deletingLastPathComponent().appending(path: "WhisperKit")
        return ModelStorageRoots(
            managedModels: models,
            hubCache: caches.appending(path: "huggingface").appending(path: "hub"),
            whisperKit:
                whisperBase
                .appending(path: "models")
                .appending(path: "argmaxinc")
                .appending(path: "whisperkit-coreml"),
            stagingCache: models.appending(path: ".hf-cache")
        )
    }
}
