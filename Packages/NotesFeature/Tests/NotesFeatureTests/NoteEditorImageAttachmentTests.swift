import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@MainActor
@Test func editorModelInsertsImageAttachmentBlock() throws {
    let note = Note(contentData: try NoteContentCoder.encode([]))
    let model = NoteEditorModel(note: note, repository: nil)
    let asset = AttachmentAsset(
        id: try #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
        originalFilename: "diagram.png",
        mimeType: "image/png",
        byteCount: 4,
        sha256: "hash",
        storagePath: "attachments/id/diagram.png"
    )

    model.insertImageAttachment(asset, after: nil)

    guard case .image(let ref, let path) = model.blocks.first?.kind else {
        Issue.record("expected image block")
        return
    }
    #expect(ref == asset.id)
    #expect(path == asset.storagePath)
}
