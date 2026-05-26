import AVFoundation
import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func micCaptureResamplesToTargetFormat() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()

    let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!
    let capture = MicrophoneCapture(writer: writer)
    let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800)!
    buffer.frameLength = 4_800
    if let channel = buffer.floatChannelData {
        for i in 0..<Int(buffer.frameLength) {
            channel[0][i] = Float.random(in: -0.1...0.1)
        }
    }
    try capture.handle(rawBuffer: buffer)
    try writer.finalize()

    try assertReadableTargetAudio(at: writer.meURL)
}

@MainActor
@Test func micCaptureReportsLevelFromRawBuffer() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mc-level-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()
    let reportedLevel = LevelBox()
    let capture = MicrophoneCapture(
        writer: writer,
        levelSink: { level in
            reportedLevel.set(level)
        })

    try capture.handle(rawBuffer: makeFloatBuffer(amplitude: 0.8))
    try writer.finalize()

    #expect(reportedLevel.value > 0.7)
}

@MainActor
@Test func appAudioCaptureDelegatesTapAndWritesTargetFormat() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ac-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()

    let tap = StubAppAudioTap()
    let capture = AppAudioCapture(writer: writer, tap: tap)

    try capture.start(pid: 123)
    #expect(tap.startedPID == 123)
    #expect(tap.stopCount == 0)

    try capture.handle(rawBuffer: makeFloatBuffer())
    capture.stop()
    #expect(tap.stopCount == 1)
    try writer.finalize()

    try assertReadableTargetAudio(at: writer.othersURL)
}

@MainActor
@Test func appAudioCaptureReportsLevelFromRawBuffer() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ac-level-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()
    let tap = StubAppAudioTap()
    let reportedLevel = LevelBox()
    let capture = AppAudioCapture(
        writer: writer, tap: tap,
        levelSink: { level in
            reportedLevel.set(level)
        })

    try capture.handle(rawBuffer: makeFloatBuffer(amplitude: 0.6))
    capture.stop()
    try writer.finalize()

    #expect(reportedLevel.value > 0.5)
}

@MainActor
@Test func appAudioCaptureStopDrainsEnqueuedWritesBeforeFinalize() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ac-drain-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()

    let tap = StubAppAudioTap()
    let capture = AppAudioCapture(writer: writer, tap: tap)
    let errors = CaptureErrorBox()

    try capture.start(pid: 456)
    capture.enqueue(rawBuffer: makeFloatBuffer()) { error in
        errors.append(error)
    }
    capture.stop()
    try writer.finalize()

    #expect(tap.startedPID == 456)
    #expect(tap.stopCount == 1)
    #expect(errors.isEmpty)
    try assertReadableTargetAudio(at: writer.othersURL)
}

#if os(macOS)
@Test func catapMapperCopiesAudioBufferListIntoPCMBuffer() throws {
    let source = makeFloatBuffer(amplitude: 0.5)
    let copied = try #require(CATapAudioBufferMapper.copy(source.audioBufferList, format: source.format))

    #expect(copied.format == source.format)
    #expect(copied.frameLength == source.frameLength)
    #expect(copied.floatChannelData?[0][0] == source.floatChannelData?[0][0])
    #expect(copied.floatChannelData?[0][Int(source.frameLength) - 1] == source.floatChannelData?[0][Int(source.frameLength) - 1])
}
#endif

private func makeFloatBuffer(amplitude: Float = 0.1) -> AVAudioPCMBuffer {
    let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800)!
    buffer.frameLength = 4_800
    if let channel = buffer.floatChannelData {
        for i in 0..<Int(buffer.frameLength) {
            channel[0][i] = amplitude
        }
    }
    return buffer
}

private func assertReadableTargetAudio(at url: URL) throws {
    let file = try AVAudioFile(forReading: url)
    let settings = file.fileFormat.settings

    #expect(file.fileFormat.sampleRate == AudioFormat.sampleRate)
    #expect(file.fileFormat.channelCount == AudioFormat.channels)
    #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
    #expect(intSetting(settings, AVFormatIDKey) == Int(kAudioFormatLinearPCM))
    #expect(intSetting(settings, AVNumberOfChannelsKey) == Int(AudioFormat.channels))
    #expect(intSetting(settings, AVLinearPCMBitDepthKey) == Int(AudioFormat.bitsPerChannel))
    #expect(boolSetting(settings, AVLinearPCMIsFloatKey) == false)
    #expect(boolSetting(settings, AVLinearPCMIsBigEndianKey) == false)
    #expect(file.length > 0)
}

private func intSetting(_ settings: [String: Any], _ key: String) -> Int? {
    (settings[key] as? NSNumber)?.intValue
}

private func boolSetting(_ settings: [String: Any], _ key: String) -> Bool? {
    (settings[key] as? NSNumber)?.boolValue
}

private final class StubAppAudioTap: AppAudioTapping, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStartedPID: pid_t?
    private var storedStopCount = 0

    var startedPID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return storedStartedPID
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedStopCount
    }

    func start(pid: pid_t) throws {
        lock.lock()
        storedStartedPID = pid
        lock.unlock()
    }

    func stop() {
        lock.lock()
        storedStopCount += 1
        lock.unlock()
    }
}

private final class CaptureErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return errors.isEmpty
    }

    func append(_ error: any Error) {
        lock.lock()
        errors.append(error)
        lock.unlock()
    }
}

private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Float = 0

    var value: Float {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Float) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}
