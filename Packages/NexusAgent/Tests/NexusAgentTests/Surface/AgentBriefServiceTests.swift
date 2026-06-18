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
    func dailyNoteStripsDigestEmphasisMarkers() {
        // The Today hero brief carries [[accent]]…[[/accent]] / [[mono]]…[[/mono]]
        // markers; a persisted note must store clean prose, not the wire tokens.
        let brief = "You have [[accent]]1 task[[/accent]] in [[mono]]bench.swift[[/mono]] today."
        let cleaned = AgentBriefDailyNoteWriter.strippingDigestMarkers(from: brief)
        #expect(cleaned == "You have 1 task in bench.swift today.")
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

    @Test
    func inputsHashIsDeterministicForIdenticalInputs() {
        let calendar = Self.utcCalendar
        let a = AgentBriefService.inputsHash(for: Self.request, calendar: calendar)
        let b = AgentBriefService.inputsHash(for: Self.request, calendar: calendar)
        #expect(a == b)
        // Stable string, not a per-launch-seeded Hasher value.
        #expect(a == "2023-11-14|o1|t2|n3|a4|Review PR\u{1F}Plan sprint")
    }

    @Test
    func inputsHashDiffersWhenCountsOrTitlesChange() {
        let calendar = Self.utcCalendar
        let base = AgentBriefService.inputsHash(for: Self.request, calendar: calendar)

        let differentCounts = AgentBriefRequest(
            counts: AgentBriefCounts(overdue: 9, today: 2, noDate: 3, awaiting: 4),
            firstTitles: ["Review PR", "Plan sprint"],
            now: Self.request.now
        )
        let differentTitles = AgentBriefRequest(
            counts: Self.request.counts,
            firstTitles: ["Different task"],
            now: Self.request.now
        )
        #expect(AgentBriefService.inputsHash(for: differentCounts, calendar: calendar) != base)
        #expect(AgentBriefService.inputsHash(for: differentTitles, calendar: calendar) != base)
    }

    @Test
    func adoptsPeerNoteWithoutInvokingRuntime() async throws {
        // Device A (agent) writes the canonical note; Device B adopts it — zero LLM.
        let calendar = Self.utcCalendar
        let context = try Self.sharedContext()

        let deviceA = try Self.makeService(
            context: context,
            calendar: calendar,
            scripts: [.text("Shared canonical brief.")]
        )
        let textA = await deviceA.service.brief(for: Self.request)
        #expect(textA == "Shared canonical brief.")
        #expect(deviceA.provider.prompts.count == 1)

        let deviceB = try Self.makeService(
            context: context,
            calendar: calendar,
            scripts: [.text("device B should NOT generate")]
        )
        let textB = await deviceB.service.brief(for: Self.request)

        // Returned text == the canonical note's read-back; runtime never ran.
        #expect(textB == "Shared canonical brief.")
        #expect(deviceB.provider.prompts.isEmpty)
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
    }

    @Test
    func legacyDeviceAdoptsAgentNoteWithoutGenerating() async throws {
        // Anti-ping-pong: a legacy-only device ADOPTS a higher-tier agent note.
        let calendar = Self.utcCalendar
        let context = try Self.sharedContext()

        let agentDevice = try Self.makeService(
            context: context,
            calendar: calendar,
            scripts: [.text("Agent-tier brief.")]
        )
        _ = await agentDevice.service.brief(for: Self.request)

        let legacyDevice = AgentBriefService(
            runtime: nil,
            threadStore: nil,
            legacy: { _ in "legacy fabricated" },
            isEnabled: { false },
            calendar: calendar,
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: context, calendar: calendar)
        )
        let text = await legacyDevice.brief(for: Self.request)
        #expect(text == "Agent-tier brief.")
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.plainText == "Agent-tier brief.")
    }

    @Test
    func changedInputsRegenerateAndUpsertNewNote() async throws {
        let calendar = Self.utcCalendar
        let context = try Self.sharedContext()
        let device = try Self.makeService(
            context: context,
            calendar: calendar,
            scripts: [.text("First brief."), .text("Second brief.")]
        )
        let first = await device.service.brief(for: Self.request)
        #expect(first == "First brief.")

        // Same day, but counts changed → new inputsHash → regenerate.
        let evolved = AgentBriefRequest(
            counts: AgentBriefCounts(overdue: 5, today: 6, noDate: 7, awaiting: 8),
            firstTitles: Self.request.firstTitles,
            now: Self.request.now
        )
        let second = await device.service.brief(for: evolved)
        #expect(second == "Second brief.")
        #expect(device.provider.prompts.count == 2)

        // One note (same day), now carrying the latest brief + inputsHash.
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.plainText == "Second brief.")
        #expect(
            Self.property(notes.first, AgentBriefDailyNoteWriter.inputsHashKey)
                == AgentBriefService.inputsHash(for: evolved, calendar: calendar)
        )
    }

    @Test
    func agentDeviceUpgradesLegacyNoteOnceThenDamps() async throws {
        let calendar = Self.utcCalendar
        let context = try Self.sharedContext()

        let legacyDevice = AgentBriefService(
            runtime: nil,
            threadStore: nil,
            legacy: { _ in "Legacy brief." },
            isEnabled: { false },
            calendar: calendar,
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: context, calendar: calendar)
        )
        _ = await legacyDevice.brief(for: Self.request)
        #expect(Self.noteSource(in: context) == AgentBriefSource.legacy.rawValue)
        // An agent device upgrades it — exactly once.
        let agentDevice = try Self.makeService(
            context: context,
            calendar: calendar,
            scripts: [.text("Upgraded agent brief."), .text("second upgrade should not happen")]
        )
        let firstUpgrade = await agentDevice.service.brief(for: Self.request)
        #expect(firstUpgrade == "Upgraded agent brief.")
        #expect(agentDevice.provider.prompts.count == 1)
        #expect(Self.noteSource(in: context) == AgentBriefSource.agent.rawValue)
        // A second reload (note now agent-tier) ADOPTS — no second runtime turn.
        let secondReload = await agentDevice.service.brief(for: Self.request)
        #expect(secondReload == "Upgraded agent brief.")
        #expect(agentDevice.provider.prompts.count == 1)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func sharedContext() throws -> ModelContext {
        try AgentBriefHarness.make(scripts: []).modelContext
    }

    private struct DeviceServices {
        let service: AgentBriefService
        let provider: AgentBriefScriptedAIProvider
    }

    private static func makeService(
        context: ModelContext,
        calendar: Calendar,
        scripts: [AgentBriefScriptedAIProvider.Script]
    ) throws -> DeviceServices {
        let harness = try AgentBriefHarness.make(context: context, scripts: scripts)
        let service = AgentBriefService(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            legacy: { _ in "legacy" },
            calendar: calendar,
            dailyNoteWriter: AgentBriefDailyNoteWriter(modelContext: context, calendar: calendar)
        )
        return DeviceServices(service: service, provider: harness.provider)
    }

    private static func noteSource(in context: ModelContext) -> String? {
        property(try? context.fetch(FetchDescriptor<Note>()).first, AgentBriefDailyNoteWriter.sourceKey)
    }

    private static func property(_ note: Note?, _ key: String) -> String? {
        guard let note, let value = note.properties.first(where: { $0.key == key })?.value,
            case .string(let string) = value
        else { return nil }
        return string
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
        try make(context: makeModelContext(), scripts: scripts)
    }

    /// Build a harness over an EXISTING context — two "devices" share one store.
    @MainActor
    static func make(
        context modelContext: ModelContext,
        scripts: [AgentBriefScriptedAIProvider.Script]
    ) throws -> AgentBriefHarness {
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
