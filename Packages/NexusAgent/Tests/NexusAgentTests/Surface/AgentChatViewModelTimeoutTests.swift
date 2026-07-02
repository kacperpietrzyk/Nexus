import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

/// Covers the bounded-turn recovery: a wall-clock timeout on the AI turn that
/// re-enables the composer AND abandons+recreates a wedged on-device engine so
/// the NEXT send runs clean. Uses the REAL `MLXProvider` / `MLXChatEngine` /
/// `AIRouter` / `AgentRuntime` stack with a stub generator that hangs, so the
/// abandon mechanism is exercised end-to-end (no hardware needed).
@MainActor
@Suite(.serialized)
struct AgentChatViewModelTimeoutTests {
    @Test("a wedged turn times out, frees the composer, recovers, and the next send succeeds")
    func timeoutRecoversAndNextSendSucceeds() async throws {
        // Initial engine hangs forever (mimics a wedged MLX.eval holding the busy
        // gate); the factory builds working engines that answer "recovered".
        let hangingEngine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
            HangingMLXChat()
        }
        let engineFactory: @Sendable () -> MLXChatEngine = {
            MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
                WorkingMLXChat(text: "recovered")
            }
        }
        let provider = MLXProvider(
            engine: hangingEngine,
            availabilityProbe: { true },
            engineFactory: engineFactory
        )
        let harness = try MLXTimeoutHarness.make(provider: provider)

        let recovered = RecoverSpy()
        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            turnTimeout: .milliseconds(300),
            recoverEngine: {
                recovered.mark()
                await harness.router.recoverMLXChat()
            }
        )

        let threadID = try harness.threadStore.create(title: "wedge")
        viewModel.selectThread(id: threadID)

        // (a) First send wedges → the wall-clock timeout must fire and free the UI.
        await viewModel.send(userMessage: "hang please")
        #expect(viewModel.isThinking == false)
        #expect(viewModel.isLoadingModel == false)
        #expect(viewModel.lastError == AgentChatViewModel.turnTimeoutMessage)

        // (b) Recovery ran (engine abandoned + recreated).
        #expect(recovered.called)

        // (c) The NEXT send succeeds on the FRESH engine — the clause that proves
        // ABANDON worked (a reset-in-place would jam behind the held busy gate).
        await viewModel.send(userMessage: "are you back")
        #expect(viewModel.isThinking == false)
        #expect(viewModel.messages.last?.role == .agent)
        #expect(viewModel.messages.last?.content == "recovered")
    }

    @Test("the model-loading phase is surfaced distinctly from generating")
    func loadingModelStateIsSurfacedWhileWarming() async throws {
        let engine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
            WorkingMLXChat(text: "hello")
        }
        let provider = MLXProvider(engine: engine, availabilityProbe: { true })
        let harness = try MLXTimeoutHarness.make(provider: provider)

        // A controlled warm closure: signals it entered, then blocks until resumed
        // so the test can observe `isLoadingModel` mid-load.
        let (enteredStream, enteredContinuation) = AsyncStream<Void>.makeStream()
        let (resumeStream, resumeContinuation) = AsyncStream<Void>.makeStream()
        let warm: @MainActor () async -> Void = {
            enteredContinuation.yield(())
            enteredContinuation.finish()
            var iter = resumeStream.makeAsyncIterator()
            _ = await iter.next()
        }

        let viewModel = AgentChatViewModel(
            runtime: harness.runtime,
            threadStore: harness.threadStore,
            messageStore: harness.messageStore,
            memoryStore: harness.memoryStore,
            warmChatModel: warm,
            recoverEngine: { await harness.router.recoverMLXChat() }
        )

        let threadID = try harness.threadStore.create(title: "loading")
        viewModel.selectThread(id: threadID)

        let sendTask = Task { @MainActor in await viewModel.send(userMessage: "hi") }

        // Wait until the warm closure is running.
        var enteredIter = enteredStream.makeAsyncIterator()
        _ = await enteredIter.next()

        // While loading: the distinct loading flag is set; not yet done thinking.
        #expect(viewModel.isLoadingModel == true)
        #expect(viewModel.isThinking == true)

        // Let the load complete → generation proceeds and finishes.
        resumeContinuation.yield(())
        resumeContinuation.finish()
        _ = await sendTask.value

        #expect(viewModel.isLoadingModel == false)
        #expect(viewModel.isThinking == false)
        #expect(viewModel.messages.last?.content == "hello")
    }
}

// MARK: - Stub generators

/// Never yields, never finishes — models a wedged `MLX.eval`.
private final class HangingMLXChat: MLXChatGenerating, @unchecked Sendable {
    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        AsyncThrowingStream { _ in }
    }

    func unload() async {}
}

/// Yields a single text chunk then finishes.
private final class WorkingMLXChat: MLXChatGenerating, @unchecked Sendable {
    private let text: String

    init(text: String) { self.text = text }

    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        let text = self.text
        return AsyncThrowingStream { continuation in
            continuation.yield(.text(text))
            continuation.finish()
        }
    }

    func unload() async {}
}

private final class RecoverSpy: @unchecked Sendable {
    private(set) var called = false
    @MainActor func mark() { called = true }
}

// MARK: - Harness

private struct MLXTimeoutHarness {
    let runtime: AgentRuntime
    let router: AIRouter
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let memoryStore: AgentMemoryStore

    @MainActor
    static func make(provider: MLXProvider) throws -> MLXTimeoutHarness {
        let modelContext = try makeModelContext()
        let threadStore = AgentThreadStore(context: modelContext)
        let messageStore = AgentMessageStore(context: modelContext)
        let memoryStore = AgentMemoryStore(context: modelContext)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: NoopRagRetriever(),
            tools: []
        )
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        #if canImport(Vision)
        let runtime = AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: makeDispatcher(modelContext: modelContext)
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

        return MLXTimeoutHarness(
            runtime: runtime,
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            memoryStore: memoryStore
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

private struct NoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
}
