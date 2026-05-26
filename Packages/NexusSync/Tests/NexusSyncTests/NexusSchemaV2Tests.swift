import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite("NexusSchemaV2")
struct NexusSchemaV2Tests {

    @Test("version is 2.0.0")
    func versionTwo() {
        #expect(NexusSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
    }

    @Test("models include V1 set + QuotaLog")
    func modelsList() {
        let names = NexusSchemaV2.models.map { String(describing: $0) }
        #expect(names.contains("Link"))
        #expect(names.contains("DebugItem"))
        #expect(names.contains("ConflictLog"))
        #expect(names.contains("QuotaLog"))
    }

    @Test("schema initializes ModelContainer in-memory")
    func makeContainer() throws {
        let schema = Schema(versionedSchema: NexusSchemaV2.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        // Round-trip: insert one of each new model in V2 to prove schema is wired.
        let context = ModelContext(container)
        context.insert(
            QuotaLog(
                id: UUID(),
                providerRaw: "appleIntelligence",
                day: .now,
                promptTokens: 1,
                completionTokens: 1
            ))
        try context.save()
    }
}
