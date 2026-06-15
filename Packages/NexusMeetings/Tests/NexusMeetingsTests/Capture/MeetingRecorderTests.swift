import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func recorderOpensWriterStartsCapturesFinalizesOnStop() async throws {
    let fixture = try RecorderFixture()
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()
    let meetingID = UUID()

    let handle = try recorder.start(meetingID: meetingID, pid: 100)

    #expect(recorder.isRecording == true)
    #expect(recorder.currentHandle()?.meetingID == meetingID)
    #expect(handle.folder.path.hasPrefix(fixture.root.path))
    #expect(fixture.mic.started == true)
    #expect(fixture.app.startedPID == 100)

    try recorder.stop()

    #expect(recorder.isRecording == false)
    #expect(recorder.currentHandle() == nil)
    #expect(fixture.mic.stopped == true)
    #expect(fixture.app.stopped == true)
    #expect(FileManager.default.fileExists(atPath: handle.meURL.path))
    #expect(FileManager.default.fileExists(atPath: handle.othersURL.path))
}

@MainActor
@Test func recorderRejectsSecondStartWhileRecording() async throws {
    let fixture = try RecorderFixture()
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()

    _ = try recorder.start(meetingID: UUID(), pid: 100)

    #expect(throws: MeetingRecorderError.alreadyRecording) {
        try recorder.start(meetingID: UUID(), pid: 200)
    }
    #expect(recorder.isRecording == true)
    try recorder.stop()
}

@MainActor
@Test func recorderRejectsStopWhenIdle() async throws {
    let fixture = try RecorderFixture()
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()

    #expect(throws: MeetingRecorderError.notRecording) {
        try recorder.stop()
    }
}

@MainActor
@Test func recorderPauseSuspendsCapturesAndResumeRestoresThem() async throws {
    let fixture = try RecorderFixture()
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()

    _ = try recorder.start(meetingID: UUID(), pid: 100)
    #expect(recorder.isPaused == false)

    try recorder.pause()

    #expect(recorder.isPaused == true)
    #expect(recorder.isRecording == true)
    #expect(fixture.mic.pausedStates == [true])
    #expect(fixture.app.pausedStates == [true])
    // Levels read zero while paused so the panel meters fall to silence.
    #expect(recorder.currentLevels().micLevel == 0)
    #expect(recorder.currentLevels().othersLevel == 0)

    try recorder.resume()

    #expect(recorder.isPaused == false)
    #expect(fixture.mic.pausedStates == [true, false])
    #expect(fixture.app.pausedStates == [true, false])

    try recorder.stop()
    #expect(recorder.isPaused == false)
}

@MainActor
@Test func recorderPauseIsIdempotentAndRejectedWhenIdle() async throws {
    let fixture = try RecorderFixture()
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()

    #expect(throws: MeetingRecorderError.notRecording) {
        try recorder.pause()
    }
    #expect(throws: MeetingRecorderError.notRecording) {
        try recorder.resume()
    }

    _ = try recorder.start(meetingID: UUID(), pid: 100)
    try recorder.pause()
    // A redundant pause is a no-op, not a second forward to the captures.
    try recorder.pause()
    #expect(fixture.mic.pausedStates == [true])

    try recorder.resume()
    try recorder.resume()
    #expect(fixture.mic.pausedStates == [true, false])

    try recorder.stop()
}

@MainActor
@Test func recorderRollsBackWhenAppCaptureStartFails() async throws {
    let fixture = try RecorderFixture(appStartError: StubCaptureError.startFailed)
    defer { fixture.cleanup() }
    let recorder = fixture.makeRecorder()
    let meetingID = UUID()
    let recordingFolder = fixture.root.appendingPathComponent(meetingID.uuidString)

    #expect(throws: StubCaptureError.startFailed) {
        try recorder.start(meetingID: meetingID, pid: 100)
    }

    #expect(recorder.isRecording == false)
    #expect(recorder.currentHandle() == nil)
    #expect(fixture.mic.started == true)
    #expect(fixture.mic.stopped == true)
    #expect(fixture.app.startedPID == 100)
    #expect(fixture.app.stopped == true)
    #expect(FileManager.default.fileExists(atPath: recordingFolder.path) == false)
    #expect(
        FileManager.default.fileExists(
            atPath: recordingFolder.appendingPathComponent("me.wav").path
        ) == false
    )
    #expect(
        FileManager.default.fileExists(
            atPath: recordingFolder.appendingPathComponent("others.wav").path
        ) == false
    )
}

private struct RecorderFixture {
    let root: URL
    let mic: FakeMicCapture
    let app: FakeAppCapture

    init(appStartError: StubCaptureError? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        mic = FakeMicCapture()
        app = FakeAppCapture(startError: appStartError)
    }

    @MainActor
    func makeRecorder() -> MeetingRecorder {
        MeetingRecorder(
            micCaptureFactory: { _ in mic },
            appCaptureFactory: { _ in app },
            rootFolder: root
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class FakeMicCapture: MeetingMicrophoneCapturing, @unchecked Sendable {
    var started = false
    var stopped = false
    var pausedStates: [Bool] = []

    func start() throws {
        started = true
    }

    func stop() {
        stopped = true
    }

    func setPaused(_ paused: Bool) {
        pausedStates.append(paused)
    }
}

private final class FakeAppCapture: MeetingAppAudioCapturing, @unchecked Sendable {
    var startedPID: pid_t?
    var stopped = false
    let startError: StubCaptureError?

    init(startError: StubCaptureError? = nil) {
        self.startError = startError
    }

    var pausedStates: [Bool] = []

    func start(pid: pid_t) throws {
        startedPID = pid
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopped = true
    }

    func setPaused(_ paused: Bool) {
        pausedStates.append(paused)
    }
}

private enum StubCaptureError: Error, Equatable {
    case startFailed
}
