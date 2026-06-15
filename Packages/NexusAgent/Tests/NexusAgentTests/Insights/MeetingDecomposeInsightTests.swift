import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct MeetingDecomposeInsightTests {
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

    private func makeCoordinator(golden: String) throws -> MeetingDecomposeCoordinator {
        MeetingDecomposeCoordinator(
            runner: SkillRunner(
                inference: ScriptedSkillInference(responses: [golden]),
                assembler: try makeAssembler()),
            scheduler: SlotScheduler(),
            workload: WorkloadAnalyzer(),
            capacity: CapacityModel(dailyCapacityMinutes: 480),
            prefs: .default,
            events: [],
            now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func eligibleWhenSummaryPresentAndNoPipelineTasks() async throws {
        let golden = #"{"tasks":[{"title":"Draft contract","estMinutes":60}]}"#
        let coordinator = try makeCoordinator(golden: golden)
        let proposal = try await MeetingDecomposeInsight.proposalIfEligible(
            summary: "We agreed to draft the contract.",
            actionItemIDs: [],
            focus: ContextFocus(),
            coordinator: coordinator)
        #expect(proposal != nil)
    }

    @Test func skippedWhenPipelineAlreadyCreatedTasks() async throws {
        let coordinator = try makeCoordinator(golden: "")
        let proposal = try await MeetingDecomposeInsight.proposalIfEligible(
            summary: "x",
            actionItemIDs: [UUID()],
            focus: ContextFocus(),
            coordinator: coordinator)
        #expect(proposal == nil)
    }
}
