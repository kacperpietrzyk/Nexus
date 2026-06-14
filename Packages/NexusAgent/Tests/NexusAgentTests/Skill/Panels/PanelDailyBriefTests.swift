import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing
@testable import NexusAgent

@MainActor
@Suite struct PanelDailyBriefTests {
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

    @Test func returnsModelSentenceOverGivenNumbers() async throws {
        let inference = ScriptedSkillInference(responses: ["You have 3 tasks due today and 1 overdue."])
        let runner = SkillRunner(inference: inference, assembler: try makeAssembler())
        let coordinator = PanelDailyBriefCoordinator(runner: runner)
        let text = try await coordinator.brief(
            summaryNumbers: "overdue=1, today=3, noDate=0, meetings=2", focus: ContextFocus())
        #expect(text.contains("3 tasks"))
        #expect(inference.requests.count == 1)
        // The given numbers were placed in the prompt (no fishing).
        #expect(inference.requests[0].prompt.contains("overdue=1"))
    }
}
