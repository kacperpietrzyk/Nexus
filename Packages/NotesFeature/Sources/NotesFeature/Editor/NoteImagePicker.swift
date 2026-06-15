import Foundation
import NexusCore

#if os(iOS)
import PhotosUI

@MainActor
enum NotePhotosImageWriter {
    static func writeTemporaryPNGData(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-photo-\(UUID().uuidString).png")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
#endif

@MainActor
struct NoteImageImporter {
    let noteRepository: NoteRepository
    let attachmentRoot: URL

    func importImage(from sourceURL: URL, into note: Note, after afterID: UUID?) throws -> AttachmentAsset {
        let storage = AttachmentImportService(root: attachmentRoot)
        let imported = try storage.importImage(from: sourceURL)
        do {
            return try noteRepository.insertImageAttachment(imported, into: note, after: afterID)
        } catch {
            storage.removeImportedFile(at: imported.storagePath)
            throw error
        }
    }
}

enum NoteAttachmentRoot {
    static func url(create: Bool = true) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let root = base.appendingPathComponent("Nexus/Attachments", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }
}
