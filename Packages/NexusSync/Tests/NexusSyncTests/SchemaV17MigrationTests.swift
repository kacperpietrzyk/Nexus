import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@Suite struct SchemaV17MigrationTests {
    @Test func v17AddsAgentInsightRecordOnTopOfV16() {
        let v17 = Set(NexusSchemaV17.models.map { String(describing: $0) })
        #expect(v17.contains("AgentInsightRecord"))
        #expect(v17.contains("FeedItemState"))
    }
    @Test func freshV17Builds() throws {
        let schema = Schema(NexusSchemaV17.models, version: NexusSchemaV17.versionIdentifier)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(AgentInsightRecord(kind: "day_plan", dedupeKey: "k", title: "t", proposalJSON: "{}"))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<AgentInsightRecord>()).count == 1)
    }
}
