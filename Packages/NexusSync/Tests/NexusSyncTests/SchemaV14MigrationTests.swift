import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("Schema V14 migration")
struct SchemaV14MigrationTests {
    @Test func schemaV14AddsAttachmentAsset() {
        #expect(NexusSchemaV14.versionIdentifier == Schema.Version(14, 0, 0))
        #expect(NexusSchemaV14.models.contains { $0 == AttachmentAsset.self })
    }

    @Test func schemaV14DeduplicatesExtraModels() {
        let assembled = NexusSchemaV14.assembledModels(extraModels: [AttachmentAsset.self])
        #expect(assembled.filter { $0 == AttachmentAsset.self }.count == 1)
    }
}
