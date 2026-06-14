import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

/// Tests for Task 4 — AgentChatViewModel proposal wiring:
/// - raw nexus-proposal block stripped from persisted content (leak landmine)
/// - pending Proposal exposed for the message id
/// - accept dispatches through ProposalCoordinator (task created + audit row)
/// - reject leaves no side effects
@MainActor
@Suite(.serialized)
struct AgentChatViewModelProposalTests {
    private static let assistantTextWithBlock = """
        Sure — I'll add that task for you.
        ```nexus-proposal
        {"rationale":"Create the task you asked for","mutations":[{"tool":"tasks.create","args":{"title":"Proposal task"}}]}
        ```
        """

    // MARK: - Leak prevention: raw block stripped from persisted content

    @Test func proposalBlockStrippedFromPersistedContent() async throws {
        let harness = try ProposalTestHarness.make(
            scriptedResponse: Self.assistantTextWithBlock
        )
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "add a task")

        // Fetch from the store directly (not the in-memory array) to confirm persistence
        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 200)
        let assistantMessage = try #require(stored.first { $0.role == .agent })
        #expect(
            assistantMessage.content.contains("nexus-proposal") == false,
            "Raw nexus-proposal block must NOT be in persisted content")
        #expect(
            assistantMessage.content.contains("I'll add that task"),
            "Display prose must be retained after stripping")
    }

    // MARK: - Pending proposal exposed for message id

    @Test func pendingProposalExposedAfterTurn() async throws {
        let harness = try ProposalTestHarness.make(
            scriptedResponse: Self.assistantTextWithBlock
        )
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "add a task")

        let agentMessage = try #require(vm.messages.first { $0.role == .agent })
        let proposal = vm.pendingProposals[agentMessage.id]
        #expect(proposal != nil, "A pending Proposal must be keyed by the agent message id")
        #expect(proposal?.mutations.first?.toolName == "tasks.create")
    }

    // MARK: - Accept dispatches mutation + writes audit row

    @Test func acceptProposalCreatesMutationAndAuditRow() async throws {
        let harness = try ProposalTestHarness.make(
            scriptedResponse: Self.assistantTextWithBlock
        )
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "add a task")

        let agentMessage = try #require(vm.messages.first { $0.role == .agent })
        try await vm.acceptProposal(messageID: agentMessage.id)

        let tasks = try harness.modelContext.fetch(FetchDescriptor<TaskItem>())
        #expect(
            tasks.contains { $0.title == "Proposal task" },
            "accept must have created the proposed task")

        let auditLogs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(!auditLogs.isEmpty, "accept must write an audit row")

        // Proposal must be cleared after accept
        #expect(
            vm.pendingProposals[agentMessage.id] == nil,
            "pending proposal must be removed after accept")
    }

    // MARK: - Reject clears proposal, no side effects

    @Test func rejectProposalLeavesNoSideEffects() async throws {
        let harness = try ProposalTestHarness.make(
            scriptedResponse: Self.assistantTextWithBlock
        )
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "add a task")

        let agentMessage = try #require(vm.messages.first { $0.role == .agent })
        vm.rejectProposal(messageID: agentMessage.id)

        let tasks = try harness.modelContext.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.isEmpty, "reject must not create any task")
        #expect(
            vm.pendingProposals[agentMessage.id] == nil,
            "pending proposal must be cleared on reject")
    }

    // MARK: - System prompt is threaded into the turn

    @Test func chatSystemPromptReachesProvider() async throws {
        let harness = try ProposalTestHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "hello")

        // The chat system prompt contains "nexus-proposal"; the default ContextBuilder
        // system prompt does NOT. Presence in the flat prompt proves threading.
        #expect(
            harness.provider.prompts.first?.contains("nexus-proposal") == true,
            "Chat system prompt (containing nexus-proposal instruction) must reach the provider")
    }

    // MARK: - Plain assistant text: no proposal, no crash

    @Test func plainTextTurnHasNoProposal() async throws {
        let harness = try ProposalTestHarness.make(scriptedResponse: "Here are your tasks.")
        let threadID = try harness.threadStore.create(title: "chat")
        let vm = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            proposalCoordinator: harness.proposalCoordinator
        )
        vm.selectThread(id: threadID)
        await vm.send(userMessage: "list tasks")

        let agentMessage = try #require(vm.messages.first { $0.role == .agent })
        #expect(vm.pendingProposals[agentMessage.id] == nil)
        #expect(agentMessage.content == "Here are your tasks.")
    }
}

// MARK: - Test harness

@MainActor
private struct ProposalTestHarness {
    let runtime: AgentRuntime
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let memoryStore: AgentMemoryStore
    let provider: ProposalScriptedProvider
    let proposalCoordinator: ProposalCoordinator
    let modelContext: ModelContext

    static func make(scriptedResponse: String) throws -> ProposalTestHarness {
        let modelContext = try makeModelContext()
        let threadStore = AgentThreadStore(context: modelContext)
        let messageStore = AgentMessageStore(context: modelContext)
        let memoryStore = AgentMemoryStore(context: modelContext)
        let provider = ProposalScriptedProvider(scriptedResponse: scriptedResponse)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: ProposalNoopRagRetriever(),
            tools: []
        )
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let dispatcher = makeDispatcher(modelContext: modelContext)
        let runtime = AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: dispatcher
        )
        return ProposalTestHarness(
            runtime: runtime,
            threadStore: threadStore,
            messageStore: messageStore,
            memoryStore: memoryStore,
            provider: provider,
            proposalCoordinator: ProposalCoordinator(dispatcher: dispatcher),
            modelContext: modelContext
        )
    }

    private static func makeModelContext() throws -> ModelContext {
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
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    // Use TasksCreateTool so accept() can create a task + write an audit row.
    private static func makeDispatcher(modelContext: ModelContext) -> ToolDispatcher {
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return ToolDispatcher(
            registry: ToolRegistry(tools: [TasksCreateTool()]),
            modelContext: modelContext,
            agentContext: agentContext
        )
    }
}

private final class ProposalScriptedProvider: AIProvider, @unchecked Sendable {
    let id: ProviderID = .appleIntelligence
    let capabilities: Set<AICapability> = [.generate, .longContext]
    let sendsDataExternally = false
    let requiresNetwork = false
    let isAvailableOnThisPlatform = true
    let supportsImageAttachments = false
    private let scriptedResponse: String
    private(set) var prompts: [String] = []

    init(scriptedResponse: String) { self.scriptedResponse = scriptedResponse }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        prompts.append(request.prompt)
        return AIResponse(
            text: scriptedResponse,
            providerUsed: id,
            tokensUsed: TokenUsage(prompt: 10, completion: 5)
        )
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse { AIResponse(text: "", providerUsed: id) }
    func embed(_ request: AIRequest) async throws -> AIResponse { AIResponse(text: "", providerUsed: id) }
}

private struct ProposalNoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
}
