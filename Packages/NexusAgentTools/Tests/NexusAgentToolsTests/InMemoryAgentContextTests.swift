import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("InMemoryAgentContext")
struct InMemoryAgentContextTests {
    @MainActor
    @Test("seeded tasks are indexed")
    func seededTasksAreIndexed() async throws {
        let task = TaskItem(title: "Needle launch checklist")

        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let hits = await fixture.context.searchIndex.search("needle", kinds: nil, limit: 10)
        #expect(hits.map(\.itemID) == [task.id])
    }
}
