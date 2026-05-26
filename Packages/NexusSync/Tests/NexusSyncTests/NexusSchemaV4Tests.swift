import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("NexusSchemaV4")
struct NexusSchemaV4Tests {
    @Test("version is 4.0.0")
    func version() {
        #expect(NexusSchemaV4.versionIdentifier == Schema.Version(4, 0, 0))
    }

    @Test("models include V3 carryovers and TaskItem")
    func modelsList() {
        let names = NexusSchemaV4.models.map { String(describing: $0) }
        #expect(names == ["Link", "DebugItem", "ConflictLog", "QuotaLog", "TaskItem"])
    }

    @MainActor
    @Test("TaskItem external source fields persist and fetch in V4 container")
    func externalSourceFieldsPersistAndFetch() throws {
        let schema = Schema(versionedSchema: NexusSchemaV4.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let metadata = Data(#"{"source":"todoist","id":"8237162"}"#.utf8)
        let task = NexusSchemaV4.TaskItem(title: "Imported from Todoist")
        task.externalSourceID = "todoist:8237162"
        task.externalSourceMetadata = metadata
        context.insert(task)
        try context.save()

        let descriptor = FetchDescriptor<NexusSchemaV4.TaskItem>(
            predicate: #Predicate { $0.externalSourceID == "todoist:8237162" }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.externalSourceMetadata == metadata)
    }

    @MainActor
    @Test("408ac35 V3 store opens with V4 migration and TaskItem external source fields default to nil")
    func migratesShippedV3FixtureWithNilExternalSourceFields() throws {
        let url = try copyFixtureStoreToTemporaryLocation()
        defer { cleanupStore(at: url) }

        let schema = Schema(versionedSchema: NexusSchemaV4.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: NexusMigrationPlan.self,
            configurations: [config]
        )
        let context = ModelContext(container)
        let fetched = try context.fetch(FetchDescriptor<NexusSchemaV4.TaskItem>())

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Pre-V4 fixture task")
        #expect(fetched.first?.externalSourceID == nil)
        #expect(fetched.first?.externalSourceMetadata == nil)
    }
}

private func copyFixtureStoreToTemporaryLocation() throws -> URL {
    // Generated from commit 408ac35 with NexusSchemaV3 and one TaskItem row.
    // The source ZTASKITEM table has no external-source columns.
    let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/nexus-v3-408ac35.store")
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-schema-v4-fixture-\(UUID().uuidString).store")

    cleanupStore(at: url)
    try FileManager.default.copyItem(at: fixtureURL, to: url)
    return url
}

private func cleanupStore(at url: URL) {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: url)
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
}
