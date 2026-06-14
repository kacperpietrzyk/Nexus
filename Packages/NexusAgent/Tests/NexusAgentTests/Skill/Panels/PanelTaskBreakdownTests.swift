import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing
@testable import NexusAgent

@MainActor
@Suite struct PanelTaskBreakdownTests {
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

    @Test func breakdownProducesNChildTasksCreateProposals() async throws {
        let golden = #"{"subtasks":["Draft outline","Write section 1","Review"]}"#
        let inference = ScriptedSkillInference(responses: [golden])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let parentID = UUID()
        let proposal = try await PanelTaskBreakdownCoordinator(runner: runner)
            .breakdown(taskID: parentID, title: "Write the report", focus: ContextFocus())
        #expect(proposal.mutations.count == 3)
        #expect(proposal.mutations.allSatisfy { $0.toolName == "tasks.create" })
        guard case .object(let a) = proposal.mutations[0].arguments else {
            Issue.record("expected parent_id in args")
            return
        }
        guard case .string(let p)? = a["parent_id"] else {
            Issue.record("expected parent_id string")
            return
        }
        #expect(p == parentID.uuidString)
    }

    @Test func contractRejectsMalformedJSON() {
        let contract = PanelTaskBreakdownSkill.outputContract
        #expect(throws: OutputContractError.self) { _ = try contract.decode("not json") }
    }

    @Test func contractRejectsEmptySubtaskList() {
        let contract = PanelTaskBreakdownSkill.outputContract
        #expect(throws: OutputContractError.self) { _ = try contract.decode(#"{"subtasks":[]}"#) }
    }
}
