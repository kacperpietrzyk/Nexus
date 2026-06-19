import SwiftData
import Testing
@testable import NexusCore

@MainActor
@Suite struct AgentInsightRepositoryTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([AgentInsightRecord.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func addThenOpenReturnsRecord() throws {
        let repo = AgentInsightRepository(context: try context())
        try repo.add(kind: "day_plan", dedupeKey: "k1", title: "Plan", proposalJSON: "{}")
        #expect(try repo.open().count == 1)
    }

    @Test func addIsDedupedByOpenDedupeKey() throws {
        let repo = AgentInsightRepository(context: try context())
        try repo.add(kind: "day_plan", dedupeKey: "k1", title: "Plan", proposalJSON: "{}")
        try repo.add(kind: "day_plan", dedupeKey: "k1", title: "Plan again", proposalJSON: "{}")
        #expect(try repo.open().count == 1)
    }

    @Test func resolveHidesFromOpen() throws {
        let repo = AgentInsightRepository(context: try context())
        let rec = try repo.add(kind: "x", dedupeKey: "k", title: "t", proposalJSON: "{}")
        try repo.resolve(id: rec.id)
        #expect(try repo.open().isEmpty)
    }
}
