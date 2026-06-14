import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing
@testable import NexusAgent

@MainActor
@Suite struct PanelTaskRefineTests {
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

    @Test func refineTitleProducesTasksUpdateProposal() async throws {
        let inference = ScriptedSkillInference(responses: ["Ship the Q3 deployment runbook"])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let coordinator = PanelTaskRefineCoordinator(runner: runner)
        let taskID = UUID()
        let proposal = try await coordinator.refine(
            field: .title, taskID: taskID, currentText: "do the deploy thing", focus: ContextFocus())
        #expect(proposal.mutations.count == 1)
        #expect(proposal.mutations[0].toolName == "tasks.update")
        guard case .object(let args) = proposal.mutations[0].arguments else {
            Issue.record("expected object args")
            return
        }
        guard case .string(let idStr)? = args["task_id"] else {
            Issue.record("expected task_id in args")
            return
        }
        #expect(idStr == taskID.uuidString)
        // preview shows old → new
        #expect(proposal.previews.first?.summary.contains("do the deploy thing") == true)
    }
}
