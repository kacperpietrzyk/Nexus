import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct FoundationCompositionTests {
    // Trivial identity skill for wiring assertions.
    private struct Out: Sendable, Equatable { let value: String }

    // MARK: - Minimal in-memory helpers for config tests

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            AgentThread.self, AgentMessage.self, AgentMemoryEntry.self,
            AgentAuditLog.self, AgentSchedule.self, ItemEmbedding.self,
            Link.self, DebugItem.self, QuotaLog.self, TaskItem.self,
            Project.self, Section.self, Comment.self, Note.self,
            ScheduledBlock.self, Label.self, Person.self, Cycle.self,
            ActivityEntry.self, SavedFilter.self, Organization.self,
            ProjectKeyDate.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeThreadStore() throws -> AgentThreadStore {
        let context = ModelContext(try makeContainer())
        return AgentThreadStore(context: context)
    }

    private func makeMessageStore() throws -> AgentMessageStore {
        let context = ModelContext(try makeContainer())
        return AgentMessageStore(context: context)
    }

    private func makeMemoryStore() throws -> AgentMemoryStore {
        let context = ModelContext(try makeContainer())
        return AgentMemoryStore(context: context)
    }

    private func makeDispatcher() throws -> ToolDispatcher {
        let container = try makeContainer()
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { now })
        let agentCtx = AgentContext(
            modelContext: ModelContextRef(context),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: SearchIndex(),
            now: { now }
        )
        return ToolDispatcher(
            registry: ToolRegistry(tools: [TasksCreateTool()]),
            modelContext: context,
            agentContext: agentCtx
        )
    }

    private func makeMinimalRuntime(dispatcher: ToolDispatcher) throws -> AgentRuntime {
        let container = try makeContainer()
        let context = ModelContext(container)
        let threadStore = AgentThreadStore(context: context)
        let messageStore = AgentMessageStore(context: context)
        let memoryStore = AgentMemoryStore(context: context)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: ConfigTestRetriever(),
            tools: []
        )
        let router = AIRouter(
            providers: [],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        return AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: dispatcher
        )
    }

    @Test func factoryBuildsWithoutThrowingAndRunnerIsUsable() async throws {
        // Build the graph from all in-memory pieces.
        let graph = try FoundationComposition.makeForTesting()

        // Prove makeRunner() yields a live SkillRunner wired to the composed assembler.
        let inference = ScriptedSkillInference(responses: ["hello"])
        let runner = graph.makeRunner(inference: inference)

        let skill = AssistantSkill(
            id: "t",
            systemPrompt: "sys",
            contextRecipe: ContextRecipe(),
            output: OutputContract<Out>(schemaDescription: "{value:string}") { Out(value: $0) }
        )
        let runResult = try await runner.run(skill, focus: ContextFocus(), userText: "hi")
        #expect(runResult.output == Out(value: "hello"))
    }

    // MARK: - Platform-correct chat config (Task 6)

    /// Verifies that `AgentChatViewModel` wired with `.mac` config has
    /// `allowsToolCalling = true` and `toolNames` non-empty.
    @Test func macChatConfigHasToolCallingEnabled() throws {
        let graph = try FoundationComposition.makeForTesting()
        let dispatcher = try makeDispatcher()
        let vm = AgentChatViewModel(
            runtime: try makeMinimalRuntime(dispatcher: dispatcher),
            threadStore: try makeThreadStore(),
            messageStore: try makeMessageStore(),
            memoryStore: try makeMemoryStore(),
            chatConfig: .mac,
            proposalCoordinator: graph.proposalCoordinator
        )
        #expect(vm.chatConfig.allowsToolCalling, "Mac config must allow tool calling")
        #expect(!vm.chatConfig.toolNames.isEmpty, "Mac config must have non-empty tool names")
    }

    /// Verifies that `AgentChatViewModel` wired with `.iOS` config has
    /// `allowsToolCalling = false` and `toolNames` empty.
    @Test func iOSChatConfigHasNoToolCalling() throws {
        let graph = try FoundationComposition.makeForTesting()
        let dispatcher = try makeDispatcher()
        let vm = AgentChatViewModel(
            runtime: try makeMinimalRuntime(dispatcher: dispatcher),
            threadStore: try makeThreadStore(),
            messageStore: try makeMessageStore(),
            memoryStore: try makeMemoryStore(),
            chatConfig: .iOS,
            proposalCoordinator: graph.proposalCoordinator
        )
        #expect(!vm.chatConfig.allowsToolCalling, "iOS config must not allow tool calling")
        #expect(vm.chatConfig.toolNames.isEmpty, "iOS config must have empty tool names")
    }

    @Test func proposalCoordinatorAcceptsMutation() async throws {
        let graph = try FoundationComposition.makeForTesting()

        let mutation = PendingMutation(
            toolName: "tasks.create",
            arguments: .object(["title": .string("Wired task")])
        )
        let proposal = Proposal(
            rationale: "test",
            mutations: [mutation],
            previews: [ProposalPreview(summary: "Create: Wired task")]
        )
        let results = try await graph.proposalCoordinator.accept(proposal, threadID: nil)
        #expect(results.count == 1)
    }
}

// MARK: - Test stubs

private struct ConfigTestRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
}
