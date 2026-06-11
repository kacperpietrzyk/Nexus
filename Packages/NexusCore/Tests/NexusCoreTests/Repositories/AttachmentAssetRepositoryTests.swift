import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Suite("AttachmentAssetRepository")
struct AttachmentAssetRepositoryTests {
    @Test func insertAndFindAttachment() throws {
        let context = try makeContext()
        let repo = AttachmentAssetRepository(context: context)
        let asset = AttachmentAsset(
            originalFilename: "a.png",
            mimeType: "image/png",
            byteCount: 3,
            sha256: "hash",
            storagePath: "attachments/a/a.png"
        )

        try repo.insert(asset)

        #expect(try repo.find(id: asset.id)?.storagePath == "attachments/a/a.png")
    }

    @Test func softDeleteHidesAttachment() throws {
        let context = try makeContext()
        let repo = AttachmentAssetRepository(context: context)
        let asset = AttachmentAsset(
            originalFilename: "a.png",
            mimeType: "image/png",
            byteCount: 1,
            sha256: "h",
            storagePath: "p"
        )
        try repo.insert(asset)

        try repo.softDelete(asset)

        #expect(try repo.find(id: asset.id) == nil)
    }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([AttachmentAsset.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}
