import Foundation
import Testing

@testable import NexusCore

@Test func attachmentAssetDefaultsAreCloudKitSafe() {
    let asset = AttachmentAsset(
        originalFilename: "diagram.png",
        mimeType: "image/png",
        byteCount: 123,
        sha256: "abc",
        storagePath: "attachments/id/diagram.png"
    )

    #expect(asset.originalFilename == "diagram.png")
    #expect(asset.mimeType == "image/png")
    #expect(asset.byteCount == 123)
    #expect(asset.sha256 == "abc")
    #expect(asset.storagePath == "attachments/id/diagram.png")
    #expect(asset.deletedAt == nil)
}

@Test func attachmentItemKindRawValueIsPinned() {
    #expect(ItemKind.attachment.rawValue == "attachment")
    #expect(ItemKind.attachment.displayName == "Attachment")
}
