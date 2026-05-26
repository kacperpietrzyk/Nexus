import Foundation
import NexusAI

#if canImport(AVFoundation)
import AVFoundation
#endif

public protocol VoiceRecorder: Sendable {
    func start() async throws
    func stop() async throws -> URL
}

public protocol VoiceTranscriber: Sendable {
    func isAvailable() async -> Bool
    func transcribe(audioURL: URL) async throws -> String
}

extension VoiceTranscriber {
    public func isAvailable() async -> Bool { true }
}

public struct AgentVoiceCaptureResult: Equatable, Sendable {
    public let audioURL: URL
    public let text: String

    public init(audioURL: URL, text: String) {
        self.audioURL = audioURL
        self.text = text
    }
}

public struct AgentVoiceCaptureSession: Sendable {
    private let recorder: any VoiceRecorder
    private let transcriber: any VoiceTranscriber
    private let retainsAudio: Bool

    public init(
        recorder: any VoiceRecorder,
        transcriber: any VoiceTranscriber,
        retainsAudio: Bool = false
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.retainsAudio = retainsAudio
    }

    public func stopAndTranscribe() async throws -> AgentVoiceCaptureResult {
        let audioURL = try await recorder.stop()
        do {
            let text = try await transcriber.transcribe(audioURL: audioURL)
            cleanup(audioURL)
            return AgentVoiceCaptureResult(audioURL: audioURL, text: text)
        } catch {
            cleanup(audioURL)
            throw error
        }
    }

    public func discard() async {
        guard let audioURL = try? await recorder.stop() else { return }
        cleanup(audioURL)
    }

    private func cleanup(_ audioURL: URL) {
        guard !retainsAudio else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }
}

public struct AgentVoiceCapture: Sendable {
    public typealias RecorderFactory = @Sendable (URL) throws -> any VoiceRecorder

    private let recorderFactory: RecorderFactory
    private let transcriber: any VoiceTranscriber
    private let temporaryURL: @Sendable () -> URL
    private let retainsAudio: Bool

    public init(
        recorderFactory: @escaping RecorderFactory,
        transcriber: any VoiceTranscriber,
        temporaryURL: @escaping @Sendable () -> URL = AgentVoiceCapture.makeTemporaryWAVURL,
        retainsAudio: Bool = false
    ) {
        self.recorderFactory = recorderFactory
        self.transcriber = transcriber
        self.temporaryURL = temporaryURL
        self.retainsAudio = retainsAudio
    }

    public func isAvailable() async -> Bool {
        await transcriber.isAvailable()
    }

    public func startRecording() async throws -> AgentVoiceCaptureSession {
        let recorder = try recorderFactory(temporaryURL())
        try await recorder.start()
        return AgentVoiceCaptureSession(
            recorder: recorder,
            transcriber: transcriber,
            retainsAudio: retainsAudio
        )
    }

    public func recordAndTranscribe() async throws -> AgentVoiceCaptureResult {
        let session = try await startRecording()
        return try await session.stopAndTranscribe()
    }

    public static func makeTemporaryWAVURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-voice-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }
}

public struct AIRouterVoiceTranscriber: VoiceTranscriber {
    private let router: AIRouter
    private let requestFactory: @Sendable (URL?) -> AIRequest

    public init(
        router: AIRouter,
        requestFactory: @escaping @Sendable (URL?) -> AIRequest = {
            AIRequest(prompt: "", capability: .transcribe, audioURL: $0)
        }
    ) {
        self.router = router
        self.requestFactory = requestFactory
    }

    public func isAvailable() async -> Bool {
        await router.hasAvailableProvider(for: requestFactory(nil))
    }

    public func transcribe(audioURL: URL) async throws -> String {
        let response = try await router.route(requestFactory(audioURL))
        return response.text
    }
}

public enum AgentVoiceCaptureError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case recorderStartFailed
    case recorderNotStarted
}

#if canImport(AVFoundation) && (os(macOS) || os(iOS))
public struct AVAudioVoiceRecorder: VoiceRecorder {
    private let box: AVAudioVoiceRecorderBox

    public init(fileURL: URL) {
        box = AVAudioVoiceRecorderBox(fileURL: fileURL)
    }

    public func start() async throws {
        try await box.start()
    }

    public func stop() async throws -> URL {
        try await box.stop()
    }
}

extension AgentVoiceCapture {
    public static func live(router: AIRouter) -> AgentVoiceCapture {
        AgentVoiceCapture(
            recorderFactory: { AVAudioVoiceRecorder(fileURL: $0) },
            transcriber: AIRouterVoiceTranscriber(router: router)
        )
    }
}

private actor AVAudioVoiceRecorderBox {
    private let fileURL: URL
    private var recorder: AVAudioRecorder?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start() async throws {
        try await configureAudioSessionIfNeeded()

        let recorder = try AVAudioRecorder(url: fileURL, settings: Self.wavSettings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw AgentVoiceCaptureError.recorderStartFailed
        }
        self.recorder = recorder
    }

    func stop() async throws -> URL {
        guard let recorder else {
            throw AgentVoiceCaptureError.recorderNotStarted
        }
        recorder.stop()
        self.recorder = nil

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return fileURL
    }

    private static var wavSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }

    private func configureAudioSessionIfNeeded() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            break
        case .denied:
            throw AgentVoiceCaptureError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard granted else {
                throw AgentVoiceCaptureError.microphonePermissionDenied
            }
        @unknown default:
            throw AgentVoiceCaptureError.microphonePermissionDenied
        }

        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        #endif
    }
}
#endif
