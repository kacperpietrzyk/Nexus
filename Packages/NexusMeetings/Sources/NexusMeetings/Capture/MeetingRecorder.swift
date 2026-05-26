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
}

public protocol MeetingAppAudioCapturing: AnyObject, Sendable {
    func start(pid: pid_t) throws
    func stop()
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
                let tap = CATapAppAudioTap { buffer in
                    sink.enqueue(buffer)
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
                let tap = CATapAppAudioTap { buffer in
                    sink.enqueue(buffer)
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
        }
        try writer.finalize()
    }

    public func currentHandle() -> RecordingHandle? {
        activeHandle
    }

    public func currentLevels() -> RecordingLevels {
        guard activeWriter != nil else { return .zero }
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
