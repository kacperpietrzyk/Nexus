import Foundation
@preconcurrency import WhisperKit

public enum WhisperKitProviderError: Error, Equatable, Sendable {
    case missingAudioURL
    case localModelUnavailable(String?)
}

/// On-device speech-to-text provider backed by WhisperKit.
///
/// Model layout — IMPORTANT. The `argmaxinc/whisperkit-coreml` variant folders
/// contain ONLY the three CoreML models (`AudioEncoder` / `MelSpectrogram` /
/// `TextDecoder`) plus `config.json`; the **tokenizer is not bundled** there —
/// WhisperKit fetches it separately (`ModelUtilities.loadTokenizer`) from the
/// original repo on first load. An earlier version of this provider required a
/// co-located `tokenizer.json`, which no downloaded variant ever provides, so
/// transcription could never become available. We now:
///   - point `localModelFolder` at the **downloaded variant folder** (persisted
///     by ``WhisperKitModelDownloadCoordinator`` after a successful download),
///   - gate availability on the three CoreML models being present (NOT the
///     tokenizer), and
///   - hand WhisperKit a `tokenizerFolder` at load time so it resolves (and
///     caches) the tokenizer itself.
public final class WhisperKitProvider: AIProvider {
    public let id: ProviderID = .whisperKit
    public let capabilities: Set<AICapability> = [.transcribe]
    public let sendsDataExternally: Bool = false
    public let requiresNetwork: Bool = false

    /// The WhisperKit variant Nexus downloads. `large-v3-turbo` is the best
    /// quality/speed multilingual tradeoff (Polish meetings) on Apple silicon.
    public static let modelVariant = "openai_whisper-large-v3-v20240930_turbo"

    /// UserDefaults key holding the on-disk path of the downloaded variant
    /// folder. Written by ``WhisperKitModelDownloadCoordinator`` on success and
    /// read by every no-arg `WhisperKitProvider()` (the composition graph and
    /// the Settings availability probe) so they all agree on the same model.
    public static let modelFolderDefaultsKey = "nexus.whisperkit.modelFolderPath"

    public var isAvailableOnThisPlatform: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return Self.isUsableLocalModelFolder(resolveModelFolder())
        #endif
    }

    /// Resolves the model folder lazily (per access) rather than capturing it at
    /// init. A provider built at launch — before any download — therefore picks
    /// up a model downloaded later in the SAME session without an app restart.
    private let resolveModelFolder: @Sendable () -> URL?
    private let engine: WhisperKitProviderEngine

    public init() {
        let resolver: @Sendable () -> URL? = { WhisperKitProvider.defaultLocalModelFolder() }
        self.resolveModelFolder = resolver
        self.engine = WhisperKitProviderEngine(
            resolveModelFolder: resolver,
            tokenizerFolder: WhisperKitProvider.defaultDownloadBase()
        )
    }

    /// Explicit-folder initializer (integration tests / advanced callers). The
    /// folder is fixed for the provider's lifetime.
    public init(localModelFolder: URL?) {
        let resolver: @Sendable () -> URL? = { localModelFolder }
        self.resolveModelFolder = resolver
        self.engine = WhisperKitProviderEngine(
            resolveModelFolder: resolver,
            tokenizerFolder: WhisperKitProvider.defaultDownloadBase()
        )
    }

    init(localModelFolder: URL?, loader: @escaping WhisperKitProviderEngine.Loader) {
        let resolver: @Sendable () -> URL? = { localModelFolder }
        self.resolveModelFolder = resolver
        self.engine = WhisperKitProviderEngine(
            resolveModelFolder: resolver,
            tokenizerFolder: nil,
            loader: loader
        )
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.whisperKit)
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        guard let audioURL = request.audioURL else {
            throw WhisperKitProviderError.missingAudioURL
        }
        let folder = resolveModelFolder()
        guard Self.isUsableLocalModelFolder(folder) else {
            throw WhisperKitProviderError.localModelUnavailable(folder?.path)
        }

        return try await engine.transcribe(audioURL: audioURL, context: request.context)
    }

    public func preload() async throws {
        let folder = resolveModelFolder()
        guard Self.isUsableLocalModelFolder(folder) else {
            throw WhisperKitProviderError.localModelUnavailable(folder?.path)
        }

        try await engine.preload()
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.whisperKit)
    }

    /// Root under which ``WhisperKitModelDownloadCoordinator`` stores the
    /// WhisperKit snapshot (`<base>/models/argmaxinc/whisperkit-coreml/<variant>`)
    /// and where the tokenizer is cached. Also the `tokenizerFolder` passed to
    /// WhisperKit at load time.
    public static func defaultDownloadBase() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Nexus", directoryHint: .isDirectory)
            .appending(path: "WhisperKit", directoryHint: .isDirectory)
    }

    /// The downloaded variant folder, or `nil` if no usable model is on disk.
    ///
    /// Prefers the path ``WhisperKitModelDownloadCoordinator`` persists on a
    /// successful download. That key is written ONLY by a download the app itself
    /// performed, so a model already present on disk — from a prior install, a
    /// migration, or a cleared key — would leave the key nil and make availability
    /// wrongly read `false` (the macOS "Not available on this device" report).
    /// When the key is absent we therefore probe WhisperKit's conventional on-disk
    /// layout and adopt an already-present model instead of giving up.
    public static func defaultLocalModelFolder() -> URL? {
        if let path = UserDefaults.standard.string(forKey: modelFolderDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let conventional = conventionalVariantFolder(), isUsableLocalModelFolder(conventional) {
            return conventional
        }
        return nil
    }

    /// WhisperKit's on-disk layout for a downloaded variant, mirroring what
    /// `WhisperKit.download(variant:downloadBase:)` produces in
    /// ``WhisperKitModelDownloadCoordinator``:
    /// `<defaultDownloadBase>/models/argmaxinc/whisperkit-coreml/<modelVariant>`.
    static func conventionalVariantFolder() -> URL? {
        defaultDownloadBase()?
            .appending(path: "models", directoryHint: .isDirectory)
            .appending(path: "argmaxinc", directoryHint: .isDirectory)
            .appending(path: "whisperkit-coreml", directoryHint: .isDirectory)
            .appending(path: modelVariant, directoryHint: .isDirectory)
    }

    /// Whether a usable WhisperKit model has been downloaded. Shared by the
    /// Settings availability probe and ``WhisperKitModelDownloadCoordinator`` so
    /// the download button and the "Local" badge agree.
    public static func isModelDownloaded() -> Bool {
        isUsableLocalModelFolder(defaultLocalModelFolder())
    }

    /// Removes the downloaded WhisperKit model folder (no delete path existed before) and
    /// clears the persisted path key, so `isModelDownloaded()` reads false and the model
    /// re-downloads on next transcription. Returns the freed byte count.
    @discardableResult
    public static func deleteDownloadedModel() -> Int64 {
        guard let folder = defaultLocalModelFolder() else { return 0 }
        let size = LiveHFFetcher.directorySize(at: folder)
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removeObject(forKey: modelFolderDefaultsKey)
        return FileManager.default.fileExists(atPath: folder.path) ? 0 : size
    }

    /// A usable model folder has the three CoreML models present (compiled
    /// `.mlmodelc` or `.mlpackage`). The tokenizer is intentionally NOT required
    /// here — WhisperKit resolves it at load time (see the type doc).
    private static func isUsableLocalModelFolder(_ folder: URL?) -> Bool {
        guard let folder else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        return requiredModelNames.allSatisfy { modelName in
            let compiledModel = folder.appending(path: "\(modelName).mlmodelc")
            let packageModel = folder.appending(
                path: "\(modelName).mlpackage/Data/com.apple.CoreML/model.mlmodel")
            return FileManager.default.fileExists(atPath: compiledModel.path)
                || FileManager.default.fileExists(atPath: packageModel.path)
        }
    }
}

protocol WhisperKitTranscribing: Sendable {
    func transcribe(audioPath: String) async throws -> String
}

final class LiveWhisperKitTranscriber: WhisperKitTranscribing, @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(modelFolder: URL, tokenizerFolder: URL?) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        self.whisperKit = try await WhisperKit(config)
    }

    func transcribe(audioPath: String) async throws -> String {
        let results = try await whisperKit.transcribe(audioPath: audioPath)
        return results.map(\.text).joined(separator: " ")
    }
}

actor WhisperKitProviderEngine {
    typealias Loader = @Sendable (URL) async throws -> any WhisperKitTranscribing

    private let resolveModelFolder: @Sendable () -> URL?
    private let loader: Loader
    private var transcriber: (any WhisperKitTranscribing)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        resolveModelFolder: @escaping @Sendable () -> URL?,
        tokenizerFolder: URL?,
        loader: Loader? = nil
    ) {
        self.resolveModelFolder = resolveModelFolder
        self.loader =
            loader
            ?? { folder in
                try await LiveWhisperKitTranscriber(
                    modelFolder: folder, tokenizerFolder: tokenizerFolder)
            }
    }

    func transcribe(audioURL: URL, context: [String]) async throws -> AIResponse {
        await enter()
        defer { leave() }

        let transcriber = try await loadIfNeeded()
        let text = try await transcriber.transcribe(audioPath: audioURL.path)
        return AIResponse(
            text: text,
            providerUsed: .whisperKit,
            citations: context
        )
    }

    func preload() async throws {
        await enter()
        defer { leave() }

        _ = try await loadIfNeeded()
    }

    private func loadIfNeeded() async throws -> any WhisperKitTranscribing {
        if let transcriber {
            return transcriber
        }
        guard let folder = resolveModelFolder() else {
            throw WhisperKitProviderError.localModelUnavailable(nil)
        }

        let loaded = try await loader(folder)
        transcriber = loaded
        return loaded
    }

    private func enter() async {
        if !busy {
            busy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func leave() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
