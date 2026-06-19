import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite struct SchemaV16MigrationTests {
    @Test func v16IncludesFeedItemStateAndKeepsV15Models() {
        let v16 = Set(NexusSchemaV16.models.map { String(describing: $0) })
        #expect(v16.contains("FeedItemState"))
        for model in NexusSchemaV15.models {
            #expect(v16.contains(String(describing: model)))
        }
    }

    @Test func freshContainerWithV16Builds() throws {
        let schema = Schema(NexusSchemaV16.models, version: NexusSchemaV16.versionIdentifier)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        context.insert(FeedItemState(key: "meeting:test"))
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<FeedItemState>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.key == "meeting:test")
    }
}
