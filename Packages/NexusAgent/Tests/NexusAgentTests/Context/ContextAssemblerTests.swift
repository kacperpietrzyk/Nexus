import Foundation
import SwiftData
import Testing
import NexusCore
import NexusAgentTools
@testable import NexusAgent

@MainActor
@Suite struct ContextAssemblerTests {
    struct StubRetriever: RagRetriever {
        let hits: [RagHit]
        func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
            Array(hits.prefix(limit))
        }
    }

    // Builds a real AgentContext over an in-memory store (see Verified contracts block).
    private func makeAgentContext(now: Date) throws -> (AgentContext, ModelContext) {
        let schema = Schema([TaskItem.self, Project.self, Person.self, Note.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let repo = TaskItemRepository(context: ctx, scheduler: RRuleScheduler(), now: { now })
        let agentContext = AgentContext(
            modelContext: ModelContextRef(ctx),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: SearchIndex(),
            now: { now })
        return (agentContext, ctx)
    }

    @Test func tasksDueSliceRendersSeededTasks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (agentContext, ctx) = try makeAgentContext(now: now)
        let due = TaskItem(title: "Write spec")
        due.dueAt = now.addingTimeInterval(3600)
        ctx.insert(due)
        try ctx.save()

        let assembler = ContextAssembler(agentContext: agentContext, retriever: StubRetriever(hits: []))
        let recipe = ContextRecipe(repoSlices: [.tasksDueWithin(days: 7)], tokenBudget: 10_000)
        let result = await assembler.assemble(recipe, focus: ContextFocus(), now: now)

        #expect(result.sections.contains { $0.title.contains("Tasks due") })
        #expect(result.sections.contains { $0.body.contains("Write spec") })
        #expect(result.estimatedTokens > 0)
    }

    @Test func overBudgetTrimsRagHitsFirst() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let (agentContext, _) = try makeAgentContext(now: now)
        let bigHits = (0..<20).map { RagHit(itemID: UUID(), kind: "note", title: "N\($0)",
                                            snippet: String(repeating: "x", count: 400), score: 1) }
        let assembler = ContextAssembler(agentContext: agentContext, retriever: StubRetriever(hits: bigHits))
        let recipe = ContextRecipe(ragQuery: RagQuerySpec(query: "x", limit: 20), tokenBudget: 300)
        let result = await assembler.assemble(recipe, focus: ContextFocus(), now: now)
        #expect(result.estimatedTokens <= 300)
    }
}
