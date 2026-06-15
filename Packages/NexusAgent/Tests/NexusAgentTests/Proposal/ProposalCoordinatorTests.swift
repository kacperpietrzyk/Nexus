import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct ProposalCoordinatorTests {
    @Test func acceptDispatchesEachMutationThroughDispatcher() async throws {
        // Build a dispatcher with a real tasks.create tool over an in-memory store.
        let harness = try ProposalHarness.make()
        let mutation = PendingMutation(toolName: "tasks.create", arguments: .object(["title": .string("From proposal")]))
        let proposal = Proposal(
            rationale: "test", mutations: [mutation],
            previews: [ProposalPreview(summary: "Create: From proposal")])
        let coordinator = ProposalCoordinator(dispatcher: harness.dispatcher)
        let results = try await coordinator.accept(proposal, threadID: nil)
        #expect(results.count == 1)
        let tasks = try harness.context.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.contains { $0.title == "From proposal" })
    }

    @Test func rejectHasNoSideEffects() async throws {
        let harness = try ProposalHarness.make()
        let coordinator = ProposalCoordinator(dispatcher: harness.dispatcher)
        let proposal = Proposal(
            rationale: "x",
            mutations: [PendingMutation(toolName: "tasks.create", arguments: .object(["title": .string("Nope")]))],
            previews: [])
        coordinator.reject(proposal)
        #expect(try harness.context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }
}

@MainActor
private struct ProposalHarness {
    let dispatcher: ToolDispatcher
    let context: ModelContext

    static func make() throws -> ProposalHarness {
        let schema = Schema([
            AgentAuditLog.self,
            Link.self,
            DebugItem.self,
            QuotaLog.self,
            TaskItem.self,
            Project.self,
            Section.self,
            Comment.self,
            Note.self,
            ScheduledBlock.self,
            Label.self,
            Person.self,
            Cycle.self,
            ActivityEntry.self,
            SavedFilter.self,
            Organization.self,
            ProjectKeyDate.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let repository = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(context),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let registry = ToolRegistry(tools: [TasksCreateTool()])
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: context,
            agentContext: agentContext
        )
        return ProposalHarness(dispatcher: dispatcher, context: context)
    }
}
