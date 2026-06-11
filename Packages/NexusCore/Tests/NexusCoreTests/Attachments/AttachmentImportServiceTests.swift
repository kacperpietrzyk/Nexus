import Foundation
import Testing

@testable import NexusCore

@Suite("AttachmentImportService")
struct AttachmentImportServiceTests {
    @Test func importImageCopiesFileAndComputesMetadata() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source image.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let id = try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        let service = AttachmentImportService(root: root)
        let result = try service.importImage(from: source, id: id)

        #expect(result.id == id)
        #expect(result.originalFilename == "source image.png")
        #expect(result.mimeType == "image/png")
        #expect(result.byteCount == 4)
        #expect(result.storagePath == "attachments/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/source-image.png")
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
        #expect(!result.sha256.isEmpty)
    }

    @Test func importImageRejectsDirectories() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let service = AttachmentImportService(root: root)
        #expect(throws: AttachmentImportError.directoryUnsupported) {
            try service.importImage(from: directory)
        }
    }

    @Test func importImageRejectsOversizedFiles() throws {
        let root = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("large.png")
        try Data(repeating: 1, count: 5).write(to: source)

        let service = AttachmentImportService(root: root, maxBytes: 4)
        #expect(throws: AttachmentImportError.fileTooLarge(actualBytes: 5, maxBytes: 4)) {
            try service.importImage(from: source)
        }
    }
}

private func makeTempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-attachment-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
