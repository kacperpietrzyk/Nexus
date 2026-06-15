import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite(.serialized)
struct AgentChatViewModelTests {
    @Test
    func viewModelLoadsMessagesForThread() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "smoke")
        _ = try harness.messageStore.append(threadID: threadID, role: .user, content: "hi")

        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)

        #expect(viewModel.messages.first?.content == "hi")
    }

    @Test
    func viewModelStoresVoiceCaptureDependencyForChatSurface() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let voiceCapture = AgentVoiceCapture(
            recorderFactory: { _ in AgentChatVoiceRecorderStub() },
            transcriber: AgentChatVoiceTranscriberStub()
        )

        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            voiceCapture: voiceCapture
        )

        #expect(viewModel.voiceCapture != nil)
    }

    @Test
    func viewModelRunTurnAppendsAssistantMessage() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "smoke")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)
        await viewModel.send(userMessage: "say hi")

        #expect(viewModel.messages.last?.role == .agent)
        #expect(viewModel.messages.last?.content == "ok")
    }

    @Test
    func viewModelStoresUserImageAttachments() async throws {
        let harness = try AgentChatViewModelHarness.make(
            scriptedResponse: "ok",
            supportsImageAttachments: true
        )
        let threadID = try harness.threadStore.create(title: "smoke")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)
        let result = await viewModel.send(userMessage: "co tu jest", attachments: ["data:image/png;base64,cG5n"])

        #expect(result == .accepted)
        #expect(viewModel.messages.first?.role == .user)
        #expect(viewModel.messages.first?.attachments == ["data:image/png;base64,cG5n"])
    }

    @Test
    func viewModelSendsContextPrefixWithoutPersistingItInUserMessage() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "file-context")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)
        let result = await viewModel.send(
            userMessage: "summarize",
            contextPrefix: "[System context]\nsecret-file-text\n[/System context]"
        )

        #expect(result == .accepted)
        #expect(viewModel.messages.first?.role == .user)
        #expect(viewModel.messages.first?.content == "summarize")
        #expect(viewModel.messages.allSatisfy { !$0.content.contains("secret-file-text") })
        #expect(harness.provider.prompts.first?.contains("secret-file-text") == true)
    }

    @Test
    func viewModelRejectsUserImageAttachmentsWithoutClearingDraftContract() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "should not be called")
        let threadID = try harness.threadStore.create(title: "smoke")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)
        let result = await viewModel.send(userMessage: "co tu jest", attachments: ["data:image/png;base64,cG5n"])

        #expect(
            result
                == .rejected("Image attachments arrive with on-device AI in the next phase.")
        )
        #expect(viewModel.lastError == "Image attachments arrive with on-device AI in the next phase.")
        #expect(viewModel.messages.isEmpty)
    }

    @Test
    func viewModelRunTurnSurfacesProviderErrorResponse() async throws {
        let harness = try AgentChatViewModelHarness.make(script: .throwing(ScriptedAgentChatError.boom))
        let threadID = try harness.threadStore.create(title: "smoke")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadID)
        await viewModel.send(userMessage: "fail")

        #expect(viewModel.lastError == "boom")
        #expect(viewModel.messages.map(\.role) == [.user])
    }

    @Test
    func viewModelStaleCompletionDoesNotClobberFresherThreadError() async throws {
        // Arrange: two threads; A is the send target, B is switched-to while send is suspended.
        let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (resumeStream, resumeContinuation) = AsyncStream<Result<Void, Error>>.makeStream()

        let harness = try AgentChatViewModelHarness.make(
            script: .controlled(entered: enteredContinuation, resume: resumeStream)
        )
        let threadA = try harness.threadStore.create(title: "thread-a")
        let threadB = try harness.threadStore.create(title: "thread-b")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: threadA)
        #expect(viewModel.lastError == nil)

        // Act: start send on A (will suspend inside generate waiting for resume signal).
        let sendTask = Task { @MainActor in
            await viewModel.send(userMessage: "will be stale")
        }

        // Wait until the scripted provider is inside generate (suspension confirmed).
        var enteredIter = enteredStream.makeAsyncIterator()
        _ = await enteredIter.next()

        // While send is suspended, switch to B — this is the §1a "nowy ⌘⇧A" race path.
        viewModel.selectThread(id: threadB)
        #expect(viewModel.currentThreadID == threadB)
        #expect(viewModel.lastError == nil)

        // Signal the suspended turn to finish with an error.
        resumeContinuation.yield(.failure(ScriptedAgentChatError.boom))
        resumeContinuation.finish()

        _ = await sendTask.value

        // Assert: the stale error must NOT have landed; B's nil lastError is preserved.
        #expect(viewModel.currentThreadID == threadB)
        #expect(viewModel.lastError == nil, "stale completion clobbered the fresher selection's lastError")
    }

    @Test
    func viewModelClearsStaleErrorOnThreadChangesCreateAndArchive() async throws {
        let harness = try AgentChatViewModelHarness.make(script: .throwing(ScriptedAgentChatError.boom))
        let firstThreadID = try harness.threadStore.create(title: "first")
        let secondThreadID = try harness.threadStore.create(title: "second")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore
        )

        viewModel.selectThread(id: firstThreadID)
        await viewModel.send(userMessage: "fail")
        #expect(viewModel.lastError == "boom")

        viewModel.selectThread(id: secondThreadID)
        #expect(viewModel.lastError == nil)

        await viewModel.send(userMessage: "fail again")
        #expect(viewModel.lastError == "boom")

        viewModel.createThread(title: "new")
        #expect(viewModel.lastError == nil)
        #expect(viewModel.currentThreadID != nil)

        await viewModel.send(userMessage: "fail after create")
        #expect(viewModel.lastError == "boom")

        let createdThreadID = try #require(viewModel.currentThreadID)
        viewModel.archive(threadID: createdThreadID)
        #expect(viewModel.lastError == nil)
        #expect(viewModel.currentThreadID == nil)
        #expect(viewModel.messages.isEmpty)
    }

    // MARK: - iOS context pre-assembly (extraction-only path)

    @Test
    func iosConfigPreAssemblesContextAndBindsRagQueryToTurn() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "ios")
        let spy = AssembleContextSpy(returnValue: "ASSEMBLED-CTX-MARKER")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .iOS,
            assembleContext: spy.closure()
        )

        viewModel.selectThread(id: threadID)
        await viewModel.send(userMessage: "what is due today")

        #expect(spy.calls.count == 1)
        // The empty iOS recipe query must be bound to this turn's message.
        #expect(spy.calls.first?.recipe.ragQuery?.query == "what is due today")
        #expect(spy.calls.first?.focus.freeText == "what is due today")
        // The assembled block must reach the provider (folded into the flat prompt).
        #expect(harness.provider.prompts.first?.contains("ASSEMBLED-CTX-MARKER") == true)
    }

    @Test
    func macConfigDoesNotPreAssembleContext() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "mac")
        let spy = AssembleContextSpy(returnValue: "SHOULD-NOT-APPEAR")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .mac,
            assembleContext: spy.closure()
        )

        viewModel.selectThread(id: threadID)
        await viewModel.send(userMessage: "hi")

        // Mac tool-calls instead of pre-stuffing; the closure must never fire.
        #expect(spy.calls.isEmpty)
        #expect(harness.provider.prompts.first?.contains("SHOULD-NOT-APPEAR") == false)
    }

    @Test
    func iosConfigMergesAssembledContextWithCallerPrefix() async throws {
        let harness = try AgentChatViewModelHarness.make(scriptedResponse: "ok")
        let threadID = try harness.threadStore.create(title: "merge")
        let spy = AssembleContextSpy(returnValue: "ASSEMBLED-MARKER")
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            chatConfig: .iOS,
            assembleContext: spy.closure()
        )

        viewModel.selectThread(id: threadID)
        // A caller prefix (e.g. file attachment) must survive alongside the assembled block.
        await viewModel.send(userMessage: "summarize", contextPrefix: "CALLER-FILE-MARKER")

        let prompt = try #require(harness.provider.prompts.first)
        #expect(prompt.contains("ASSEMBLED-MARKER"))
        #expect(prompt.contains("CALLER-FILE-MARKER"))
    }
}

/// Records the recipe/focus passed to the injected context-assembly closure and
/// returns a fixed marker string, so tests can assert both invocation and threading.
@MainActor
private final class AssembleContextSpy {
    private(set) var calls: [(recipe: ContextRecipe, focus: ContextFocus)] = []
    private let returnValue: String

    init(returnValue: String) { self.returnValue = returnValue }

    func closure() -> (@MainActor (ContextRecipe, ContextFocus, Date) async -> String) {
        { recipe, focus, _ in
            self.calls.append((recipe, focus))
            return self.returnValue
        }
    }
}

private struct AgentChatViewModelHarness {
    let runtime: AgentRuntime
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let memoryStore: AgentMemoryStore
    let provider: AgentChatScriptedAIProvider

    @MainActor
    static func make(
        scriptedResponse: String,
        supportsImageAttachments: Bool = false
    ) throws -> AgentChatViewModelHarness {
        try make(script: .text(scriptedResponse), supportsImageAttachments: supportsImageAttachments)
    }

    @MainActor
    static func make(
        script: AgentChatScriptedAIProvider.Script,
        supportsImageAttachments: Bool = false
    ) throws -> AgentChatViewModelHarness {
        let modelContext = try makeModelContext()
        let threadStore = AgentThreadStore(context: modelContext)
        let messageStore = AgentMessageStore(context: modelContext)
        let memoryStore = AgentMemoryStore(context: modelContext)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: AgentChatNoopRagRetriever(),
            tools: []
        )
        let provider = AgentChatScriptedAIProvider(
            script: script,
            id: supportsImageAttachments ? .whisperKit : .appleIntelligence,
            sendsDataExternally: supportsImageAttachments,
            requiresNetwork: supportsImageAttachments,
            supportsImageAttachments: supportsImageAttachments
        )
        let consentStore: any ConsentStore =
            supportsImageAttachments ? AgentChatAllowAllConsentStore() : InMemoryConsentStore()
        let router = AIRouter(
            providers: [provider],
            consent: consentStore,
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        #if canImport(Vision)
        let runtime = AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: makeDispatcher(modelContext: modelContext),
            ocrPipeline: supportsImageAttachments ? OCRPipeline() : nil
        )
        #else
        let runtime = AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: makeDispatcher(modelContext: modelContext)
        )
        #endif

        return AgentChatViewModelHarness(
            runtime: runtime,
            threadStore: threadStore,
            messageStore: messageStore,
            memoryStore: memoryStore,
            provider: provider
        )
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
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return ToolDispatcher(
            registry: ToolRegistry(tools: []),
            modelContext: modelContext,
            agentContext: agentContext
        )
    }
}

private enum ScriptedAgentChatError: Error, CustomStringConvertible {
    case boom

    var description: String {
        switch self {
        case .boom:
            "boom"
        }
    }
}

private struct AgentChatNoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        []
    }
}

private struct AgentChatVoiceRecorderStub: VoiceRecorder {
    func start() async throws {}
    func stop() async throws -> URL { URL(fileURLWithPath: "/tmp/agent-chat.wav") }
}

private struct AgentChatVoiceTranscriberStub: VoiceTranscriber {
    func transcribe(audioURL _: URL) async throws -> String { "voice" }
}

private final class AgentChatScriptedAIProvider: AIProvider, @unchecked Sendable {
    enum Script: Sendable {
        case text(String)
        case throwing(any Error)
        /// Signals `entered` when generate is called, then awaits `resume` before
        /// returning or throwing. Used to inject mid-await thread switches in tests.
        case controlled(
            entered: AsyncStream<Void>.Continuation,
            resume: AsyncStream<Result<Void, Error>>
        )
    }

    let id: ProviderID
    let capabilities: Set<AICapability> = [.generate, .longContext]
    let sendsDataExternally: Bool
    let requiresNetwork: Bool
    let isAvailableOnThisPlatform = true
    let supportsImageAttachments: Bool

    private let script: Script
    private(set) var prompts: [String] = []

    init(
        script: Script,
        id: ProviderID = .appleIntelligence,
        sendsDataExternally: Bool = false,
        requiresNetwork: Bool = false,
        supportsImageAttachments: Bool = false
    ) {
        self.script = script
        self.id = id
        self.sendsDataExternally = sendsDataExternally
        self.requiresNetwork = requiresNetwork
        self.supportsImageAttachments = supportsImageAttachments
    }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        prompts.append(request.prompt)
        switch script {
        case .text(let text):
            return AIResponse(
                text: text,
                providerUsed: id,
                tokensUsed: TokenUsage(prompt: 10, completion: 5)
            )
        case .throwing(let error):
            throw error
        case .controlled(let entered, let resume):
            entered.yield(())
            entered.finish()
            var iter = resume.makeAsyncIterator()
            let result = await iter.next() ?? .success(())
            switch result {
            case .success:
                return AIResponse(text: "controlled-ok", providerUsed: id)
            case .failure(let error):
                throw error
            }
        }
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }

    func embed(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }
}

private struct AgentChatAllowAllConsentStore: ConsentStore {
    func hasConsent(for provider: ProviderID) async -> Bool { true }
    func setConsent(_ granted: Bool, for provider: ProviderID) async {}
}
