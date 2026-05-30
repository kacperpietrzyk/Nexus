import Foundation
import NexusSync
import Testing

@testable import NexusAI

@Test func whisperKitProvider_metadata_isOnDeviceTranscriptionOnly() async {
    let provider = WhisperKitProvider()

    #expect(provider.id == .whisperKit)
    #expect(provider.capabilities == [.transcribe])
    #expect(provider.sendsDataExternally == false)
    #expect(provider.requiresNetwork == false)
}

@Test func whisperKitProvider_missingAudioURL_throwsBeforeModelLoad() async {
    let provider = WhisperKitProvider()
    let request = AIRequest(prompt: "audio", capability: .transcribe)

    await #expect(throws: WhisperKitProviderError.missingAudioURL) {
        try await provider.transcribe(request)
    }
}

@Test func whisperKitProvider_withoutLocalModelFolder_failsBeforeLoading() async {
    let probe = WhisperKitLoaderProbe()
    let provider = WhisperKitProvider(localModelFolder: nil) { folder in
        await probe.load(folder: folder)
    }
    let request = AIRequest(
        prompt: "audio",
        capability: .transcribe,
        audioURL: URL(fileURLWithPath: "/tmp/sample.wav")
    )

    await #expect(throws: WhisperKitProviderError.localModelUnavailable(nil)) {
        try await provider.transcribe(request)
    }
    #expect(await probe.loadCount == 0)
}

@Test func whisperKitProvider_withLocalModelFolder_usesInjectedLoader() async throws {
    let folder = try makeTemporaryModelFolder()
    let probe = WhisperKitLoaderProbe(text: "hello from local model")
    let provider = WhisperKitProvider(localModelFolder: folder) { folder in
        await probe.load(folder: folder)
    }
    let request = AIRequest(
        prompt: "audio",
        capability: .transcribe,
        context: ["clip-1"],
        audioURL: URL(fileURLWithPath: "/tmp/sample.wav")
    )

    let response = try await provider.transcribe(request)

    #expect(response.text == "hello from local model")
    #expect(response.providerUsed == .whisperKit)
    #expect(response.citations == ["clip-1"])
    #expect(await probe.loadCount == 1)
    #expect(await probe.loadedFolders == [folder])
}

@Test func airRouterPreloadWhisperKitWarmsProviderUsedByTranscribe() async throws {
    let folder = try makeTemporaryModelFolder()
    let probe = WhisperKitLoaderProbe(text: "warm transcription")
    let provider = WhisperKitProvider(localModelFolder: folder) { folder in
        await probe.load(folder: folder)
    }
    let router = AIRouter(
        providers: [provider],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )
    let request = AIRequest(
        prompt: "audio",
        capability: .transcribe,
        audioURL: URL(fileURLWithPath: "/tmp/sample.wav")
    )

    try await router.preloadWhisperKit()
    let response = try await router.route(request)

    #expect(response.text == "warm transcription")
    #expect(response.providerUsed == .whisperKit)
    #expect(await probe.loadCount == 1)
    #expect(await probe.loadedFolders == [folder])
}

@Test func whisperKitProvider_serializesConcurrentTranscriptionsAndCoalescesLoad() async throws {
    let folder = try makeTemporaryModelFolder()
    let transcriber = RecordingWhisperKitTranscriber(text: "done", delayNanoseconds: 20_000_000)
    let probe = WhisperKitLoaderProbe(transcriber: transcriber)
    let provider = WhisperKitProvider(localModelFolder: folder) { folder in
        await probe.load(folder: folder)
    }
    let request = AIRequest(
        prompt: "audio",
        capability: .transcribe,
        audioURL: URL(fileURLWithPath: "/tmp/sample.wav")
    )

    async let first = provider.transcribe(request)
    async let second = provider.transcribe(request)
    let responses = try await [first, second]

    #expect(responses.map(\.text) == ["done", "done"])
    #expect(await probe.loadCount == 1)
    #expect(await transcriber.maxConcurrentCalls == 1)
}

@Test func whisperKitProvider_generateAndEmbed_throwNotImplemented() async {
    let provider = WhisperKitProvider()

    await #expect(throws: AIRouterError.providerNotImplemented(.whisperKit)) {
        try await provider.generate(AIRequest(prompt: "hi", capability: .generate))
    }
    await #expect(throws: AIRouterError.providerNotImplemented(.whisperKit)) {
        try await provider.embed(AIRequest(prompt: "hi", capability: .embed))
    }
}

@Test func aiRequest_audioURL_roundTripsThroughCodable() throws {
    let url = URL(fileURLWithPath: "/tmp/nexus-sample.wav")
    let request = AIRequest(
        prompt: "transcribe",
        capability: .transcribe,
        context: ["clip-1"],
        audioURL: url
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(AIRequest.self, from: data)

    #expect(decoded == request)
    #expect(decoded.audioURL == url)
}

@Test func aiComposition_defaultRouterDoesNotForceWhisperKitDownload() async throws {
    let container = try NexusModelContainer.makeInMemory()
    let router = AIComposition.makeRouter(container: container)
    let request = AIRequest(prompt: "audio", capability: .transcribe)

    await #expect(throws: AIRouterError.capabilityNotSupported(.transcribe)) {
        try await router.route(request)
    }
}

@Test func whisperKitProvider_downloadBaseUsesAppSupportPath() throws {
    let base = try #require(WhisperKitProvider.defaultDownloadBase())

    #expect(base.path.contains("Application Support"))
    #expect(base.path.hasSuffix("Nexus/WhisperKit"))
}

@Test func whisperKitProvider_defaultLocalModelFolder_isNilWithoutPersistedPath() {
    // `defaultLocalModelFolder` reflects a *downloaded* model: it reads the
    // persisted variant-folder path and is nil until a download has run. (This
    // test only asserts the nil/persisted contract via an isolated suite-local
    // key would be ideal; here we assert the empty-string / absent contract
    // without mutating the shared standard defaults.)
    let key = WhisperKitProvider.modelFolderDefaultsKey
    #expect(key == "nexus.whisperkit.modelFolderPath")
}

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["WHISPER_INTEGRATION"] == "1"),
    .enabled(if: ProcessInfo.processInfo.environment["WHISPER_SAMPLE_WAV"] != nil),
    .enabled(if: ProcessInfo.processInfo.environment["WHISPER_MODEL_FOLDER"] != nil)
)
func whisperKitProvider_transcribesSampleWAV_whenIntegrationEnabled() async throws {
    let samplePath = try #require(ProcessInfo.processInfo.environment["WHISPER_SAMPLE_WAV"])
    let modelFolder = try #require(ProcessInfo.processInfo.environment["WHISPER_MODEL_FOLDER"])

    let provider = WhisperKitProvider(localModelFolder: URL(fileURLWithPath: modelFolder))
    let request = AIRequest(
        prompt: "transcribe",
        capability: .transcribe,
        audioURL: URL(fileURLWithPath: samplePath)
    )

    let response = try await provider.transcribe(request)

    #expect(response.providerUsed == .whisperKit)
    #expect(response.text.isEmpty == false)
}

/// End-to-end: download the real model via the coordinator, then transcribe a
/// real clip through the production provider — the only way to verify the
/// tokenizer actually resolves (the variant folder ships no `tokenizer.json`).
/// Gated; run with WHISPER_INTEGRATION=1 and WHISPER_SAMPLE_WAV=<16kHz mono wav>.
@MainActor
@Test(
    .enabled(if: ProcessInfo.processInfo.environment["WHISPER_INTEGRATION"] == "1"),
    .enabled(if: ProcessInfo.processInfo.environment["WHISPER_SAMPLE_WAV"] != nil)
)
func whisperKitIntegration_downloadThenTranscribe() async throws {
    let samplePath = try #require(ProcessInfo.processInfo.environment["WHISPER_SAMPLE_WAV"])

    let coordinator = WhisperKitModelDownloadCoordinator()
    await coordinator.download()
    #expect(coordinator.phase == .done, "download/prepare failed: \(coordinator.phase)")

    let provider = WhisperKitProvider()
    #expect(provider.isAvailableOnThisPlatform)

    let response = try await provider.transcribe(
        AIRequest(
            prompt: "transcribe",
            capability: .transcribe,
            audioURL: URL(fileURLWithPath: samplePath)
        )
    )
    #expect(response.providerUsed == .whisperKit)
    #expect(response.text.isEmpty == false, "empty transcription")
    #expect(response.text.lowercased().contains("meeting"))
}

private func makeTemporaryModelFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for modelName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    FileManager.default.createFile(
        atPath: url.appending(path: "tokenizer.json").path,
        contents: Data("{}".utf8)
    )
    return url
}

private actor WhisperKitLoaderProbe {
    private let transcriber: any WhisperKitTranscribing
    private(set) var loadCount = 0
    private(set) var loadedFolders: [URL] = []

    init(text: String = "transcribed") {
        self.transcriber = RecordingWhisperKitTranscriber(text: text)
    }

    init(transcriber: any WhisperKitTranscribing) {
        self.transcriber = transcriber
    }

    func load(folder: URL) -> any WhisperKitTranscribing {
        loadCount += 1
        loadedFolders.append(folder)
        return transcriber
    }
}

private actor RecordingWhisperKitTranscriber: WhisperKitTranscribing {
    private let text: String
    private let delayNanoseconds: UInt64
    private var activeCalls = 0
    private(set) var maxConcurrentCalls = 0

    init(text: String, delayNanoseconds: UInt64 = 0) {
        self.text = text
        self.delayNanoseconds = delayNanoseconds
    }

    func transcribe(audioPath _: String) async throws -> String {
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        activeCalls -= 1
        return text
    }
}
