import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite(.serialized)
struct AgentBriefServiceTests {
    @Test
    func disabledOrMissingRuntimeUsesLegacyBrief() async {
        let service = AgentBriefService(
            runtime: nil,
            threadStore: nil,
            legacy: { request in "legacy \(request.counts.today)" },
            isEnabled: { false }
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "legacy 2")
    }

    @Test
    func disabledRuntimeDoesNotCreateThreadOrMessages() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.text("should not run")])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy disabled" },
            isEnabled: { false }
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "legacy disabled")
        #expect(harness.provider.prompts.isEmpty)
        #expect(try harness.threadStore.allActive().isEmpty)
        #expect(try harness.allMessages().isEmpty)
    }

    @Test
    func runtimeSuccessReturnsAgentText() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.text("  Agentowy brief.  \n")])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" }
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "Agentowy brief.")
        let threads = try harness.threadStore.allActive()
        #expect(threads.map(\.title) == ["Daily Briefs"])
        #expect(harness.provider.prompts.first?.contains("Write today's brief for the Today view in Nexus") == true)
    }

    @Test
    func runtimeSuccessUpsertsDailyNote() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.text("  Agent daily brief.  \n")])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" },
            calendar: calendar,
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: harness.modelContext, calendar: calendar)
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "Agent daily brief.")
        let notes = try harness.modelContext.fetch(FetchDescriptor<Note>())
        let note = try #require(notes.first)
        #expect(notes.count == 1)
        #expect(note.title == "Daily Brief 2023-11-14")
        #expect(note.role == .dailyNote)
        #expect(note.tags == ["daily", "2023-11-14"])
        #expect(note.plainText == "Agent daily brief.")
    }

    @Test
    func dailyNoteUpsertIsIdentityStableAndSpawnsNoTasks() async throws {
        // A brief with a checkbox, "read" twice (the second is a cache-hit).
        let harness = try AgentBriefHarness.make(scripts: [.text("Plan:\n- [ ] Ship it\n")])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" },
            calendar: calendar,
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: harness.modelContext, calendar: calendar)
        )

        _ = await service.brief(for: Self.request)
        let contentAfterFirst = try #require(
            try harness.modelContext.fetch(FetchDescriptor<Note>()).first
        ).contentData

        _ = await service.brief(for: Self.request)  // cache-hit — must not churn the note

        let notes = try harness.modelContext.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        // Identity-stable: the unchanged brief did not rewrite the note (no fresh refs).
        #expect(notes.first?.contentData == contentAfterFirst)
        // The checkbox never spawned a task — no duplicate Inbox tasks on re-read (SW1).
        #expect(try harness.modelContext.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test
    func sameKeySequentialCallsUseCachedTextWithoutSecondRuntimeTurn() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.text("Agent once")])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" }
        )

        let first = await service.brief(for: Self.request)
        let second = await service.brief(for: Self.request)

        #expect(first == "Agent once")
        #expect(second == "Agent once")
        #expect(harness.provider.prompts.count == 1)
        #expect(try harness.allMessages().map(\.role) == [.user, .agent])
    }

    @Test
    func sameKeyConcurrentCallsCoalesceIntoOneRuntimeTurn() async throws {
        let gate = AgentBriefProviderGate()
        let harness = try AgentBriefHarness.make(scripts: [.delayed("Coalesced brief", gate)])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" }
        )

        async let first = service.brief(for: Self.request)
        await gate.waitUntilSuspended()
        async let second = service.brief(for: Self.request)
        await Task.yield()
        await gate.resumeAll()

        let texts = await (first, second)

        #expect(texts.0 == "Coalesced brief")
        #expect(texts.1 == "Coalesced brief")
        #expect(harness.provider.prompts.count == 1)
        #expect(try harness.allMessages().map(\.role) == [.user, .agent])
    }

    @Test
    func providerErrorFallsBackToLegacyBrief() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.throwing(AgentBriefProviderError.boom)])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy fallback" }
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "legacy fallback")
    }

    @Test
    func providerErrorFallbackIsCachedForSameKey() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.throwing(AgentBriefProviderError.boom)])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy cached fallback" }
        )

        let first = await service.brief(for: Self.request)
        let second = await service.brief(for: Self.request)

        #expect(first == "legacy cached fallback")
        #expect(second == "legacy cached fallback")
        #expect(harness.provider.prompts.count == 1)
        #expect(try harness.allMessages().map(\.role) == [.user])
    }

    @Test
    func emptyCompletedResponseFallsBackToLegacyBrief() async throws {
        let harness = try AgentBriefHarness.make(scripts: [.text(" \n ")])
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy empty" }
        )

        let text = await service.brief(for: Self.request)

        #expect(text == "legacy empty")
    }

    private static let request = AgentBriefRequest(
        counts: AgentBriefCounts(overdue: 1, today: 2, noDate: 3, awaiting: 4),
        firstTitles: ["Review PR", "Plan sprint"],
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private struct AgentBriefHarness {
    let modelContext: ModelContext
    let runtime: AgentRuntime
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let provider: AgentBriefScriptedAIProvider

    @MainActor
    static func make(scripts: [AgentBriefScriptedAIProvider.Script]) throws -> AgentBriefHarness {
        let modelContext = try makeModelContext()
        let threadStore = AgentThreadStore(context: modelContext)
        let messageStore = AgentMessageStore(context: modelContext)
        let memoryStore = AgentMemoryStore(context: modelContext)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: AgentBriefNoopRagRetriever(),
            tools: []
        )
        let provider = AgentBriefScriptedAIProvider(scripts: scripts)
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        return AgentBriefHarness(
            modelContext: modelContext,
            runtime: AgentRuntime(
                router: router,
                threadStore: threadStore,
                messageStore: messageStore,
                contextBuilder: contextBuilder,
                dispatcher: makeDispatcher(modelContext: modelContext)
            ),
            threadStore: threadStore,
            messageStore: messageStore,
            provider: provider
        )
    }

    func allMessages() throws -> [AgentMessage] {
        guard let threadID = try threadStore.allActive().first?.id else {
            return []
        }
        return try messageStore.slidingWindow(threadID: threadID, last: 50)
    }

    private static func makeModelContext() throws -> ModelContext {
        let schema = Schema([
            AgentThread.self,
            AgentMessage.self,
            AgentMemoryEntry.self,
            AgentAuditLog.self,
            AgentSchedule.self,
            ItemEmbedding.self,
            Link.self,
            Note.self,
            Project.self,
            Section.self,
            DebugItem.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @MainActor
    private static func makeDispatcher(modelContext: ModelContext) -> ToolDispatcher {
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return ToolDispatcher(
            registry: ToolRegistry(tools: []),
            modelContext: modelContext,
            agentContext: AgentContext(
                modelContext: ModelContextRef(modelContext),
                taskRepository: TaskItemRepositoryRef(repository),
                searchIndex: SearchIndex(),
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        )
    }
}

private struct AgentBriefNoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        []
    }
}

private actor AgentBriefProviderGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitUntilSuspended() async {
        while waiters.isEmpty {
            await Task.yield()
        }
    }

    func resumeAll() {
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private enum AgentBriefProviderError: Error, CustomStringConvertible {
    case boom

    var description: String {
        switch self {
        case .boom: "boom"
        }
    }
}

private final class AgentBriefScriptedAIProvider: AIProvider, @unchecked Sendable {
    enum Script: Sendable {
        case text(String)
        case delayed(String, AgentBriefProviderGate)
        case throwing(any Error)
    }

    let id: ProviderID = .appleIntelligence
    let capabilities: Set<AICapability> = [.generate, .longContext]
    let sendsDataExternally = false
    let requiresNetwork = false
    let isAvailableOnThisPlatform = true

    private var scripts: [Script]
    private(set) var prompts: [String] = []

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        prompts.append(request.prompt)
        let script = scripts.isEmpty ? .text("") : scripts.removeFirst()
        switch script {
        case .text(let text):
            return AIResponse(
                text: text,
                providerUsed: id,
                tokensUsed: TokenUsage(prompt: 10, completion: 5)
            )
        case .delayed(let text, let gate):
            await gate.wait()
            return AIResponse(
                text: text,
                providerUsed: id,
                tokensUsed: TokenUsage(prompt: 10, completion: 5)
            )
        case .throwing(let error):
            throw error
        }
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }

    func embed(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }
}
