import Foundation
import Testing

@testable import NexusMeetings

/// Deterministic capturer: returns canned text and records how many times it was
/// asked to capture, so a test can assert the OFF path never touches the screen.
private actor SpyScreenContextCapture: ScreenContextCapturing {
    private let text: String?
    private(set) var captureCount = 0

    init(returning text: String?) {
        self.text = text
    }

    func captureText() async throws -> String? {
        captureCount += 1
        return text
    }
}

struct ScreenContextStageTests {
    private func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-stage-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func disabledNeverCapturesAndWritesNothing() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = SpyScreenContextCapture(returning: "should not appear")
        let stage = ScreenContextStage(capture: spy, isEnabled: { false })

        let result = try await stage.capture(folder: folder)

        #expect(result == nil)
        await #expect(spy.captureCount == 0)
        #expect(FileManager.default.fileExists(atPath: folder.path) == false)
        #expect(ScreenContextStore().combinedText(folder: folder) == nil)
    }

    @Test func enabledCapturesAndAppendsText() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = SpyScreenContextCapture(returning: "Sprint board: 3 in progress")
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })

        let result = try await stage.capture(folder: folder)

        #expect(result == "Sprint board: 3 in progress")
        await #expect(spy.captureCount == 1)
        #expect(ScreenContextStore().combinedText(folder: folder) == "Sprint board: 3 in progress")
    }

    @Test func enabledButNoRecognizedTextWritesNothing() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let spy = SpyScreenContextCapture(returning: nil)
        let stage = ScreenContextStage(capture: spy, isEnabled: { true })

        let result = try await stage.capture(folder: folder)

        #expect(result == nil)
        await #expect(spy.captureCount == 1)
        #expect(ScreenContextStore().combinedText(folder: folder) == nil)
    }
}
