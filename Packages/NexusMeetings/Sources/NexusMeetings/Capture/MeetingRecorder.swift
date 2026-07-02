import AVFoundation
import Foundation

public struct RecordingHandle: Sendable {
    public let meetingID: UUID
    public let folder: URL

    public var meURL: URL { folder.appendingPathComponent("me.wav") }
    public var othersURL: URL { folder.appendingPathComponent("others.wav") }
}

public enum MeetingRecorderError: Error, Equatable {
    case alreadyRecording
    case notRecording
}

public protocol MeetingMicrophoneCapturing: AnyObject, Sendable {
    func start() throws
    func stop()
    /// Suspend (or resume) writing captured audio to disk without tearing down
    /// the underlying engine, so a pause/resume keeps the same file open.
    func setPaused(_ paused: Bool)
}

public protocol MeetingAppAudioCapturing: AnyObject, Sendable {
    func start(pid: pid_t) throws
    func stop()
    /// Suspend (or resume) writing captured audio to disk without tearing down
    /// the underlying process tap, so a pause/resume keeps the same file open.
    func setPaused(_ paused: Bool)
}

extension MeetingMicrophoneCapturing {
    public func setPaused(_ paused: Bool) {}
}

extension MeetingAppAudioCapturing {
    public func setPaused(_ paused: Bool) {}
}

extension MicrophoneCapture: MeetingMicrophoneCapturing {}
extension AppAudioCapture: MeetingAppAudioCapturing {}

@MainActor
public final class MeetingRecorder {
    private let writerFactory: (URL) throws -> AudioFileWriter
    private let micCaptureFactory: (AudioFileWriter, AudioLevelStore) -> any MeetingMicrophoneCapturing
    private let appCaptureFactory: (AudioFileWriter, AudioLevelStore) -> any MeetingAppAudioCapturing
    private let rootFolder: URL
    private let levelStore = AudioLevelStore()

    private var activeWriter: AudioFileWriter?
    private var activeMic: (any MeetingMicrophoneCapturing)?
    private var activeApp: (any MeetingAppAudioCapturing)?
    private var activeHandle: RecordingHandle?
    private var paused = false

    public init(
        writerFactory: @escaping (URL) throws -> AudioFileWriter = { try AudioFileWriter(folder: $0) },
        micCaptureFactory: @escaping (AudioFileWriter) -> any MeetingMicrophoneCapturing = {
            MicrophoneCapture(writer: $0)
        },
        appCaptureFactory: @escaping (AudioFileWriter) -> any MeetingAppAudioCapturing,
        rootFolder: URL
    ) {
        self.writerFactory = writerFactory
        self.micCaptureFactory = { writer, _ in micCaptureFactory(writer) }
        self.appCaptureFactory = { writer, _ in appCaptureFactory(writer) }
        self.rootFolder = rootFolder
    }

    private init(
        writerFactory: @escaping (URL) throws -> AudioFileWriter,
        micCaptureFactory: @escaping (AudioFileWriter, AudioLevelStore) -> any MeetingMicrophoneCapturing,
        appCaptureFactory: @escaping (AudioFileWriter, AudioLevelStore) -> any MeetingAppAudioCapturing,
        rootFolder: URL
    ) {
        self.writerFactory = writerFactory
        self.micCaptureFactory = micCaptureFactory
        self.appCaptureFactory = appCaptureFactory
        self.rootFolder = rootFolder
    }

    #if os(macOS)
    public convenience init(
        writerFactory: @escaping (URL) throws -> AudioFileWriter = { try AudioFileWriter(folder: $0) },
        rootFolder: URL
    ) {
        self.init(
            writerFactory: writerFactory,
            micCaptureFactory: { writer, levelStore in
                MicrophoneCapture(
                    writer: writer,
                    levelSink: { level in
                        levelStore.updateMic(level)
                    })
            },
            appCaptureFactory: { writer, levelStore in
                let sink = AppAudioCaptureSink()
                // Capture `sink` weakly: the tap holds `onBuffer` strongly and the
                // sink holds `capture` (which holds the tap) strongly, so a strong
                // capture here closes a retain cycle that leaks the whole
                // capture/converter graph on every stop. `sink` outlives each buffer
                // callback via the strong chain, so a weak ref is safe.
                let tap = CATapAppAudioTap { [weak sink] buffer in
                    sink?.enqueue(buffer)
                }
                let capture = AppAudioCapture(
                    writer: writer, tap: tap,
                    levelSink: { level in
                        levelStore.updateOthers(level)
                    })
                sink.set(capture)
                return capture
            },
            rootFolder: rootFolder
        )
    }

    public convenience init(
        writerFactory: @escaping (URL) throws -> AudioFileWriter = { try AudioFileWriter(folder: $0) },
        micCaptureFactory: @escaping (AudioFileWriter) -> any MeetingMicrophoneCapturing,
        rootFolder: URL
    ) {
        self.init(
            writerFactory: writerFactory,
            micCaptureFactory: { writer, _ in
                micCaptureFactory(writer)
            },
            appCaptureFactory: { writer, levelStore in
                let sink = AppAudioCaptureSink()
                // Capture `sink` weakly: the tap holds `onBuffer` strongly and the
                // sink holds `capture` (which holds the tap) strongly, so a strong
                // capture here closes a retain cycle that leaks the whole
                // capture/converter graph on every stop. `sink` outlives each buffer
                // callback via the strong chain, so a weak ref is safe.
                let tap = CATapAppAudioTap { [weak sink] buffer in
                    sink?.enqueue(buffer)
                }
                let capture = AppAudioCapture(
                    writer: writer, tap: tap,
                    levelSink: { level in
                        levelStore.updateOthers(level)
                    })
                sink.set(capture)
                return capture
            },
            rootFolder: rootFolder
        )
    }
    #endif

    public var isRecording: Bool { activeWriter != nil }

    @discardableResult
    public func start(meetingID: UUID, pid: pid_t) throws -> RecordingHandle {
        guard activeWriter == nil else { throw MeetingRecorderError.alreadyRecording }

        let folder = rootFolder.appendingPathComponent(meetingID.uuidString)
        let writer = try writerFactory(folder)
        levelStore.reset()
        do {
            try writer.openTracks()
            let mic = micCaptureFactory(writer, levelStore)
            let app = appCaptureFactory(writer, levelStore)
            do {
                try mic.start()
                try app.start(pid: pid)
            } catch {
                mic.stop()
                app.stop()
                throw error
            }

            let handle = RecordingHandle(meetingID: meetingID, folder: writer.folder)
            activeWriter = writer
            activeMic = mic
            activeApp = app
            activeHandle = handle
            paused = false
            return handle
        } catch {
            cleanupFailedStart(writer: writer)
            throw error
        }
    }

    public func stop() throws {
        guard let writer = activeWriter else { throw MeetingRecorderError.notRecording }
        activeMic?.stop()
        activeApp?.stop()
        defer {
            activeWriter = nil
            activeMic = nil
            activeApp = nil
            activeHandle = nil
            paused = false
        }
        try writer.finalize()
    }

    public var isPaused: Bool { paused }

    /// Suspend audio capture without finalizing the file: the engine/tap stay
    /// alive but stop writing frames, so `resume()` continues the same recording
    /// (the gap is simply silence). Idempotent while already paused.
    public func pause() throws {
        guard activeWriter != nil else { throw MeetingRecorderError.notRecording }
        guard paused == false else { return }
        paused = true
        activeMic?.setPaused(true)
        activeApp?.setPaused(true)
        levelStore.reset()
    }

    /// Resume a paused recording. Idempotent while already running.
    public func resume() throws {
        guard activeWriter != nil else { throw MeetingRecorderError.notRecording }
        guard paused else { return }
        paused = false
        activeMic?.setPaused(false)
        activeApp?.setPaused(false)
    }

    public func currentHandle() -> RecordingHandle? {
        activeHandle
    }

    public func currentLevels() -> RecordingLevels {
        guard activeWriter != nil else { return .zero }
        // While paused no frames flow, so report silence (the level store still
        // holds the last pre-pause snapshot) — the panel meters fall to zero.
        guard paused == false else { return .zero }
        return levelStore.snapshot()
    }

    private func cleanupFailedStart(writer: AudioFileWriter) {
        try? writer.finalize()
        try? FileManager.default.removeItem(at: writer.folder)
    }
}

#if os(macOS)
private final class AppAudioCaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var capture: AppAudioCapture?

    func set(_ capture: AppAudioCapture) {
        lock.lock()
        self.capture = capture
        lock.unlock()
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let capture = capture
        lock.unlock()
        capture?.enqueue(rawBuffer: buffer)
    }
}
#endif
