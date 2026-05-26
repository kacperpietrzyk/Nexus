import Foundation
import NexusAI
import Testing

@testable import NexusAgent

@MainActor
@Test func voiceCaptureProducesTranscriptViaProvider() async throws {
    let stubURL = FileManager.default.temporaryDirectory.appending(path: "x.wav")
    _ = FileManager.default.createFile(atPath: stubURL.path, contents: Data([0x52, 0x49, 0x46, 0x46]))
    let capture = AgentVoiceCapture(
        recorderFactory: { _ in StubRecorder(fileURL: stubURL) },
        transcriber: StubTranscriber(scripted: "ok")
    )

    let result = try await capture.recordAndTranscribe()

    #expect(result.audioURL == stubURL)
    #expect(result.text == "ok")
    #expect(!FileManager.default.fileExists(atPath: stubURL.path))
}

@MainActor
@Test func voiceCaptureCanRetainAudioWhenRequested() async throws {
    let stubURL = FileManager.default.temporaryDirectory.appending(path: "agent-voice-retained.wav")
    _ = FileManager.default.createFile(atPath: stubURL.path, contents: Data([0x52, 0x49, 0x46, 0x46]))
    let capture = AgentVoiceCapture(
        recorderFactory: { _ in StubRecorder(fileURL: stubURL) },
        transcriber: StubTranscriber(scripted: "ok"),
        retainsAudio: true
    )

    _ = try await capture.recordAndTranscribe()

    #expect(FileManager.default.fileExists(atPath: stubURL.path))
    try? FileManager.default.removeItem(at: stubURL)
}

@MainActor
@Test func voiceCaptureDeletesAudioWhenTranscriptionFails() async throws {
    let stubURL = FileManager.default.temporaryDirectory.appending(path: "agent-voice-failed.wav")
    _ = FileManager.default.createFile(atPath: stubURL.path, contents: Data([0x52, 0x49, 0x46, 0x46]))
    let capture = AgentVoiceCapture(
        recorderFactory: { _ in StubRecorder(fileURL: stubURL) },
        transcriber: ThrowingTranscriber(),
        retainsAudio: false
    )

    await #expect(throws: StubVoiceError.boom) {
        try await capture.recordAndTranscribe()
    }
    #expect(!FileManager.default.fileExists(atPath: stubURL.path))
}

@MainActor
@Test func voiceCaptureSessionDiscardStopsAndDeletesAudio() async throws {
    let stubURL = FileManager.default.temporaryDirectory.appending(path: "agent-voice-discarded.wav")
    _ = FileManager.default.createFile(atPath: stubURL.path, contents: Data([0x52, 0x49, 0x46, 0x46]))
    let capture = AgentVoiceCapture(
        recorderFactory: { _ in StubRecorder(fileURL: stubURL) },
        transcriber: StubTranscriber(scripted: "unused")
    )
    let session = try await capture.startRecording()

    await session.discard()

    #expect(!FileManager.default.fileExists(atPath: stubURL.path))
}

@MainActor
@Test func aiRouterVoiceTranscriberRoutesTranscribeRequestWithAudioURL() async throws {
    let provider = RecordingTranscribeProvider(responseText: "voice transcript")
    let router = AIRouter(
        providers: [provider],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )
    let transcriber = AIRouterVoiceTranscriber(router: router)
    let audioURL = URL(fileURLWithPath: "/tmp/agent-router.wav")

    #expect(await transcriber.isAvailable())
    let text = try await transcriber.transcribe(audioURL: audioURL)

    #expect(text == "voice transcript")
    #expect(await provider.lastRequest?.capability == .transcribe)
    #expect(await provider.lastRequest?.audioURL == audioURL)
}

@MainActor
@Test func aiRouterVoiceTranscriberUnavailableWhenNoOfflineTranscribeProviderCanRoute() async {
    let router = AIRouter(
        providers: [
            RecordingTranscribeProvider(
                isAvailableOnThisPlatform: false,
                responseText: "unavailable"
            )
        ],
        consent: InMemoryConsentStore(),
        quota: InMemoryQuotaTracker(),
        secrets: InMemorySecretStore()
    )
    let transcriber = AIRouterVoiceTranscriber(router: router)

    #expect(await transcriber.isAvailable() == false)
}

private struct StubRecorder: VoiceRecorder {
    let fileURL: URL

    func start() async throws {}
    func stop() async throws -> URL { fileURL }
}

private struct StubTranscriber: VoiceTranscriber {
    let scripted: String

    func transcribe(audioURL _: URL) async throws -> String { scripted }
}

private enum StubVoiceError: Error {
    case boom
}

private struct ThrowingTranscriber: VoiceTranscriber {
    func transcribe(audioURL _: URL) async throws -> String {
        throw StubVoiceError.boom
    }
}

private actor RecordingTranscribeProvider: AIProvider {
    let id: ProviderID = .whisperKit
    let capabilities: Set<AICapability> = [.transcribe]
    let sendsDataExternally = false
    let requiresNetwork = false
    let isAvailableOnThisPlatform: Bool
    private let responseText: String
    private(set) var lastRequest: AIRequest?

    init(isAvailableOnThisPlatform: Bool = true, responseText: String) {
        self.isAvailableOnThisPlatform = isAvailableOnThisPlatform
        self.responseText = responseText
    }

    nonisolated func generate(_: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(id)
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        lastRequest = request
        return AIResponse(text: responseText, providerUsed: id)
    }

    nonisolated func embed(_: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(id)
    }
}
