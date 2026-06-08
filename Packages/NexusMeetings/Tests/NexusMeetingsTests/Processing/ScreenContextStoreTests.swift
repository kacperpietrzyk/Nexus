import Foundation
import Testing

@testable import NexusMeetings

struct ScreenContextStoreTests {
    private func makeFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-context-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func readReturnsEmptyWhenNoFile() throws {
        let folder = makeFolder()
        let store = ScreenContextStore()
        #expect(try store.read(folder: folder).isEmpty)
        #expect(store.combinedText(folder: folder) == nil)
    }

    @Test func appendThenReadRoundTrips() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenContextStore()
        try store.append(text: "Roadmap Q3", folder: folder)
        try store.append(text: "Budget slide", folder: folder)
        #expect(try store.read(folder: folder) == ["Roadmap Q3", "Budget slide"])
        #expect(store.combinedText(folder: folder) == "Roadmap Q3\n\nBudget slide")
    }

    @Test func appendSkipsConsecutiveDuplicate() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenContextStore()
        try store.append(text: "Same window", folder: folder)
        try store.append(text: "Same window", folder: folder)
        #expect(try store.read(folder: folder) == ["Same window"])
    }

    @Test func appendIgnoresBlankText() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenContextStore()
        try store.append(text: "   \n  ", folder: folder)
        #expect(try store.read(folder: folder).isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("screen_context.txt").path) == false)
    }

    @Test func storeOnlyEverHoldsTextNeverFrames() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ScreenContextStore()
        try store.append(text: "Slide text", folder: folder)
        // The only file the store writes is the text sidecar — no image artifacts.
        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(contents == ["screen_context.txt"])
    }
}
