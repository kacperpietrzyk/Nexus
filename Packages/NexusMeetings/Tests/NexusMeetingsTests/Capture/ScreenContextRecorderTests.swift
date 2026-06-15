import Foundation
import Testing

@testable import NexusMeetings

/// Deterministic capturer that counts invocations and can signal a continuation
/// once it has been asked to capture at least `expected` times, so the test can
/// await a known number of capture cycles without sleeping.
private actor CountingScreenContextCapture: ScreenContextCapturing {
    private var count = 0
    private let text: String?
    private let expected: Int
    private var continuation: CheckedContinuation<Void, Never>?

    init(returning text: String?, expected: Int) {
        self.text = text
        self.expected = expected
    }

    var captureCount: Int { count }

    func captureText() async throws -> String? {
        count += 1
        if count >= expected, let cont = continuation {
            continuation = nil
            cont.resume()
        }
        return text
    }

    func waitForExpected() async {
        if count >= expected { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
        }
    }
}

/// Throws a transient error for the first `failures` captures, then succeeds.
/// Used to prove a single bad frame does not kill OCR for the whole meeting.
private actor TransientThenSucceedCapture: ScreenContextCapturing {
    private(set) var captureCount = 0
    private let failures: Int
    private let expected: Int
    private var continuation: CheckedContinuation<Void, Never>?

    init(failures: Int, expected: Int) {
        self.failures = failures
        self.expected = expected
    }

    func captureText() async throws -> String? {
        captureCount += 1
        let current = captureCount
        if current >= expected, let cont = continuation {
            continuation = nil
            cont.resume()
        }
        if current <= failures {
            throw ScreenContextCaptureError.noShareableContent
        }
        return "ok"
    }

    func waitForExpected() async {
        if captureCount >= expected { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
        }
    }
}

/// Throws an unrecoverable error (no capture path on this platform) on every call.
private actor FatalThrowingScreenContextCapture: ScreenContextCapturing {
    private(set) var captureCount = 0

    func captureText() async throws -> String? {
        captureCount += 1
        throw ScreenContextCaptureError.unsupportedPlatform
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var waiter: CheckedContinuation<Void, Never>?

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func record(_ error: any Error) {
        lock.lock()
        _count += 1
        let cont = waiter
        waiter = nil
        lock.unlock()
        cont?.resume()
    }

    func waitForFirst() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if _count > 0 {
                lock.unlock()
                cont.resume()
                return
            }
            waiter = cont
            lock.unlock()
        }
    }
}

@MainActor
struct ScreenContextRecorderTests {
    private func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-recorder-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func disabledNeverStartsCaptureLoop() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = CountingScreenContextCapture(returning: "nope", expected: 1)
        let stage = ScreenContextStage(capture: spy, isEnabled: { false })
        let recorder = ScreenContextRecorder(
            stage: stage,
            cadence: .milliseconds(5),
            isEnabled: { false }
        )

        recorder.start(folder: folder)
        // Give any (incorrectly started) loop a chance to fire.
        try await Task.sleep(nanoseconds: 50_000_000)
        recorder.stop()

        await #expect(spy.captureCount == 0)
        #expect(FileManager.default.fileExists(atPath: folder.path) == false)
    }

    @Test func enabledCapturesPeriodicallyAndWritesSidecar() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = CountingScreenContextCapture(returning: "Board: 3 in progress", expected: 2)
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })
        let recorder = ScreenContextRecorder(
            stage: stage,
            cadence: .milliseconds(5),
            isEnabled: { true }
        )

        recorder.start(folder: folder)
        await spy.waitForExpected()
        recorder.stop()

        await #expect(spy.captureCount >= 2)
        #expect(ScreenContextStore().combinedText(folder: folder) == "Board: 3 in progress")
    }

    @Test func transientCaptureErrorIsSurfacedButLoopContinues() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // First frame throws a transient error, the loop must recover and a
        // later frame must succeed and write the sidecar. `expected: 3` leaves a
        // full cadence after the first success frame so its `store.append`
        // settles before the waiter resumes.
        let spy = TransientThenSucceedCapture(failures: 1, expected: 3)
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })
        let errorBox = ErrorBox()
        let recorder = ScreenContextRecorder(
            stage: stage,
            cadence: .milliseconds(5),
            isEnabled: { true },
            onCaptureError: { error in errorBox.record(error) }
        )

        recorder.start(folder: folder)
        await spy.waitForExpected()
        recorder.stop()

        // The transient error was surfaced, but a single bad frame did not kill
        // OCR for the meeting: the loop kept going and produced text.
        #expect(errorBox.count >= 1)
        await #expect(spy.captureCount >= 2)
        #expect(ScreenContextStore().combinedText(folder: folder) == "ok")
    }

    @Test func fatalCaptureErrorIsSurfacedAndStopsLoop() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = FatalThrowingScreenContextCapture()
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })
        let errorBox = ErrorBox()
        let recorder = ScreenContextRecorder(
            stage: stage,
            cadence: .milliseconds(5),
            isEnabled: { true },
            onCaptureError: { error in errorBox.record(error) }
        )

        recorder.start(folder: folder)
        await errorBox.waitForFirst()
        recorder.stop()
        // Allow any (incorrectly continued) loop iterations to fire.
        try await Task.sleep(nanoseconds: 50_000_000)

        // An unrecoverable capture is reported once and halts the loop.
        #expect(errorBox.count == 1)
        await #expect(spy.captureCount == 1)
    }

    @Test func stopHaltsFurtherCaptures() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = CountingScreenContextCapture(returning: "x", expected: 1)
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })
        let recorder = ScreenContextRecorder(
            stage: stage,
            cadence: .milliseconds(5),
            isEnabled: { true }
        )

        recorder.start(folder: folder)
        await spy.waitForExpected()
        recorder.stop()
        let countAfterStop = await spy.captureCount
        try await Task.sleep(nanoseconds: 50_000_000)

        // No more than a single in-flight capture may complete after stop.
        await #expect(spy.captureCount <= countAfterStop + 1)
    }
}
