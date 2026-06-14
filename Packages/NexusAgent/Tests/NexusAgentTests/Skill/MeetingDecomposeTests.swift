import Foundation
import SwiftData
import Testing
import NexusCore        // TaskItem, RRuleScheduler, SearchIndex
import NexusAgentTools  // AgentContext, ModelContextRef, TaskItemRepositoryRef
@testable import NexusAgent

@MainActor
@Suite struct MeetingDecomposeTests {
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

    @Test func goldenSummaryProducesProposalWithTaskCreateMutations() async throws {
        let golden = #"{"tasks":[{"title":"Draft contract","estMinutes":90},{"title":"Email client","estMinutes":30}]}"#
        let inference = ScriptedSkillInference(responses: [golden])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let coordinator = MeetingDecomposeCoordinator(
            runner: runner, scheduler: SlotScheduler(), workload: WorkloadAnalyzer(),
            capacity: CapacityModel(dailyCapacityMinutes: 240),
            prefs: .default, events: [], now: Date(timeIntervalSince1970: 1_800_000_000))

        let proposal = try await coordinator.decompose(
            summary: "We agreed to draft the contract and email the client.",
            focus: ContextFocus())

        #expect(proposal.mutations.count == 2)
        #expect(proposal.mutations.allSatisfy { $0.toolName == "tasks.create" })
        #expect(proposal.previews.count == 2)
        #expect(proposal.rationale.isEmpty == false)
    }

    @Test func contractRejectsMalformedJSON() {
        let contract = MeetingDecomposeSkill.outputContract
        #expect(throws: OutputContractError.self) { _ = try contract.decode("not json") }
    }
}
