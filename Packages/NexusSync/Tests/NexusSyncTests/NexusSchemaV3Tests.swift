import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("NexusSchemaV3")
struct NexusSchemaV3Tests {
    @Test("version is 3.0.0")
    func version() {
        #expect(NexusSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
    }

    @Test("models include V2 carryovers and TaskItem")
    func modelsList() {
        let names = NexusSchemaV3.models.map { String(describing: $0) }
        #expect(names.contains("Link"))
        #expect(names.contains("DebugItem"))
        #expect(names.contains("ConflictLog"))
        #expect(names.contains("QuotaLog"))
        #expect(names.contains("TaskItem"))
    }

    @MainActor
    @Test("TaskItem persists in V3 container")
    func taskItemPersistable() throws {
        let schema = Schema(versionedSchema: NexusSchemaV3.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.insert(NexusSchemaV3.TaskItem(title: "schema smoke"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<NexusSchemaV3.TaskItem>())
        #expect(fetched.count == 1)
    }
}
