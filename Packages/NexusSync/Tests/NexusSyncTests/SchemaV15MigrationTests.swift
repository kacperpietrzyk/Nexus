import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("Schema V15 migration")
struct SchemaV15MigrationTests {
    @Test func schemaV15AddsOrganizationAndKeyDate() {
        #expect(NexusSchemaV15.versionIdentifier == Schema.Version(15, 0, 0))
        #expect(NexusSchemaV15.models.contains { $0 == Organization.self })
        #expect(NexusSchemaV15.models.contains { $0 == ProjectKeyDate.self })
    }

    @Test func schemaV15IsSupersetOfV14() {
        #expect(NexusSchemaV15.models.count == NexusSchemaV14.models.count + 2)
    }

    @Test func schemaV15DeduplicatesExtraModels() {
        let assembled = NexusSchemaV15.assembledModels(extraModels: [Organization.self])
        #expect(assembled.filter { $0 == Organization.self }.count == 1)
    }
}
