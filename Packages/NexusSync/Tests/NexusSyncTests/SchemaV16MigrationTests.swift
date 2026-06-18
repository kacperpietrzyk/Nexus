import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("Schema V16 migration")
struct SchemaV16MigrationTests {
    @Test func schemaV16HasVersion16() {
        #expect(NexusSchemaV16.versionIdentifier == Schema.Version(16, 0, 0))
    }

    @Test func schemaV16KeepsV15ModelSet() {
        #expect(NexusSchemaV16.models.count == NexusSchemaV15.models.count)
    }

    @Test func migrationPlanIncludesV16() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV16.self })
    }
}
