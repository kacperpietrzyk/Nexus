import Foundation
@preconcurrency import WhisperKit

public enum WhisperKitProviderError: Error, Equatable, Sendable {
    case missingAudioURL
    case localModelUnavailable(String?)
}

/// On-device speech-to-text provider backed by WhisperKit.
public final class WhisperKitProvider: AIProvider {
    public let id: ProviderID = .whisperKit
    public let capabilities: Set<AICapability> = [.transcribe]
    public let sendsDataExternally: Bool = false
    public let requiresNetwork: Bool = false

    public var isAvailableOnThisPlatform: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return Self.isUsableLocalModelFolder(localModelFolder)
        #endif
    }

    private let localModelFolder: URL?
    private let engine: WhisperKitProviderEngine

    public init(localModelFolder: URL? = WhisperKitProvider.defaultLocalModelFolder()) {
        self.localModelFolder = localModelFolder
        self.engine = WhisperKitProviderEngine(localModelFolder: localModelFolder)
    }

    init(localModelFolder: URL?, loader: @escaping WhisperKitProviderEngine.Loader) {
        self.localModelFolder = localModelFolder
        self.engine = WhisperKitProviderEngine(localModelFolder: localModelFolder, loader: loader)
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.whisperKit)
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        guard let audioURL = request.audioURL else {
            throw WhisperKitProviderError.missingAudioURL
        }
        guard Self.isUsableLocalModelFolder(localModelFolder) else {
            throw WhisperKitProviderError.localModelUnavailable(localModelFolder?.path)
        }

        return try await engine.transcribe(audioURL: audioURL, context: request.context)
    }

    public func preload() async throws {
        guard Self.isUsableLocalModelFolder(localModelFolder) else {
            throw WhisperKitProviderError.localModelUnavailable(localModelFolder?.path)
        }

        try await engine.preload()
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.whisperKit)
    }

    public static func defaultLocalModelFolder() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Nexus", directoryHint: .isDirectory)
            .appending(path: "WhisperKit", directoryHint: .isDirectory)
    }

    private static func isUsableLocalModelFolder(_ folder: URL?) -> Bool {
        guard let folder else { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]
        let hasRequiredModels = requiredModelNames.allSatisfy { modelName in
            let compiledModel = folder.appending(path: "\(modelName).mlmodelc")
            let packageModel = folder.appending(
                path: "\(modelName).mlpackage/Data/com.apple.CoreML/model.mlmodel")
            return FileManager.default.fileExists(atPath: compiledModel.path)
                || FileManager.default.fileExists(atPath: packageModel.path)
        }
        let hasLocalTokenizer = FileManager.default.fileExists(
            atPath: folder.appending(path: "tokenizer.json").path)

        return hasRequiredModels && hasLocalTokenizer
    }
}

protocol WhisperKitTranscribing: Sendable {
    func transcribe(audioPath: String) async throws -> String
}

final class LiveWhisperKitTranscriber: WhisperKitTranscribing, @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(modelFolder: URL) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
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

    private let localModelFolder: URL?
    private let loader: Loader
    private var transcriber: (any WhisperKitTranscribing)?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(
        localModelFolder: URL?,
        loader: @escaping Loader = { folder in
            try await LiveWhisperKitTranscriber(modelFolder: folder)
        }
    ) {
        self.localModelFolder = localModelFolder
        self.loader = loader
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
        guard let localModelFolder else {
            throw WhisperKitProviderError.localModelUnavailable(nil)
        }

        let loaded = try await loader(localModelFolder)
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
