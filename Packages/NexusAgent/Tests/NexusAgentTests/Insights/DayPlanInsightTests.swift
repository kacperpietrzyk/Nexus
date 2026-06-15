import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct DayPlanInsightTests {
    private func makeAssembler() throws -> ContextAssembler {
        let schema = Schema([TaskItem.self, Project.self, Person.self, Note.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let repo = TaskItemRepository(context: ctx, scheduler: RRuleScheduler(), now: { .now })
        let agentContext = AgentContext(
            modelContext: ModelContextRef(ctx),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: SearchIndex(),
            now: { .now })
        struct Empty: RagRetriever {
            func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
        }
        return ContextAssembler(agentContext: agentContext, retriever: Empty())
    }

    @Test func scriptedInferenceProducesAdviceOnlyProposal() async throws {
        let ordering = "Start with the contract review, then tackle the email follow-ups."
        let runner = SkillRunner(
            inference: ScriptedSkillInference(responses: [ordering]),
            assembler: try makeAssembler())
        let proposal = try await DayPlanInsight.proposal(
            runner: runner,
            summaryNumbers: "3 tasks due, 1 overdue",
            focus: ContextFocus(),
            now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(proposal.mutations.isEmpty)
        #expect(proposal.rationale == ordering)
    }
}
