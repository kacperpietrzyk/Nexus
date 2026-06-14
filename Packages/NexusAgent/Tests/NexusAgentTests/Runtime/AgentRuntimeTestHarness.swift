import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

// Shared in-memory test harness + scripted provider/tools for the AgentRuntime
// turn-loop suites. Extracted from `AgentRuntimeTurnLoopTests.swift` so each test
// file stays under the strict `file_length` gate; semantics are unchanged.

struct RuntimeHarness {
    let runtime: AgentRuntime
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let modelContext: ModelContext
    let provider: ScriptedAgentAIProvider

    @MainActor
    static func make(
        tools: [any AgentTool],
        scripts: [ScriptedAgentAIProvider.Script],
        supportsImageAttachments: Bool = false
    ) throws -> RuntimeHarness {
        try makeInner(
            tools: tools,
            scripts: scripts,
            supportsImageAttachments: supportsImageAttachments,
            ocrPipeline: nil
        )
    }

    #if canImport(Vision)
    @MainActor
    static func make(
        tools: [any AgentTool],
        scripts: [ScriptedAgentAIProvider.Script],
        supportsImageAttachments: Bool = false,
        ocrPipeline: OCRPipeline?
    ) throws -> RuntimeHarness {
        try makeInner(
            tools: tools,
            scripts: scripts,
            supportsImageAttachments: supportsImageAttachments,
            ocrPipeline: ocrPipeline
        )
    }
    #endif

    @MainActor
    private static func makeInner(
        tools: [any AgentTool],
        scripts: [ScriptedAgentAIProvider.Script],
        supportsImageAttachments: Bool,
        ocrPipeline: (any Sendable)?
    ) throws -> RuntimeHarness {
        let modelContext = try makeModelContext()
        let threadStore = AgentThreadStore(context: modelContext)
        let messageStore = AgentMessageStore(context: modelContext)
        let memoryStore = AgentMemoryStore(context: modelContext)
        let contextBuilder = ContextBuilder(
            memoryStore: memoryStore,
            messageStore: messageStore,
            retriever: NoopRagRetriever(),
            tools: tools
        )
        let provider = ScriptedAgentAIProvider(
            scripts: scripts,
            id: supportsImageAttachments ? .whisperKit : .appleIntelligence,
            sendsDataExternally: supportsImageAttachments,
            requiresNetwork: supportsImageAttachments,
            supportsImageAttachments: supportsImageAttachments
        )
        let consentStore: any ConsentStore =
            supportsImageAttachments ? AllowAllConsentStore() : InMemoryConsentStore()
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
            dispatcher: makeDispatcher(modelContext: modelContext, tools: tools),
            ocrPipeline: ocrPipeline as? OCRPipeline
        )
        #else
        let runtime = AgentRuntime(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: makeDispatcher(modelContext: modelContext, tools: tools)
        )
        #endif

        return RuntimeHarness(
            runtime: runtime,
            threadStore: threadStore,
            messageStore: messageStore,
            modelContext: modelContext,
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
    private static func makeDispatcher(
        modelContext: ModelContext,
        tools: [any AgentTool]
    ) -> ToolDispatcher {
        ToolDispatcher(
            registry: ToolRegistry(tools: tools),
            modelContext: modelContext,
            agentContext: makeAgentContext(modelContext: modelContext)
        )
    }

    @MainActor
    private static func makeAgentContext(modelContext: ModelContext) -> AgentContext {
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }
}

// `NoopRagRetriever` is deliberately file-private, matching the existing per-file
// convention (each test file declares its own private copy of this stub to avoid
// same-target redeclaration collisions). The turn-loop test file owns its own
// private `EchoTool` for the same reason.
private struct NoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        []
    }
}

enum ScriptedProviderError: Error, CustomStringConvertible {
    case boom

    var description: String {
        switch self {
        case .boom: "boom"
        }
    }
}

final class ScriptedAgentAIProvider: AIProvider, @unchecked Sendable {
    enum Script: Sendable {
        case text(String)
        case throwing(any Error)
        /// Structured tool calls returned alongside `text` (native tool-calling
        /// providers like MLX populate `AIResponse.toolCalls`).
        case structured(text: String, toolCalls: [AIToolCall])
    }

    let id: ProviderID
    let capabilities: Set<AICapability> = [.generate, .longContext]
    let sendsDataExternally: Bool
    let requiresNetwork: Bool
    let isAvailableOnThisPlatform = true
    let supportsImageAttachments: Bool

    private var scripts: [Script]
    private(set) var callCount = 0
    private(set) var prompts: [String] = []
    /// Tool specs received in the most-recent `generate` call.
    private(set) var lastToolSpecs: [AIToolSpec] = []

    init(
        scripts: [Script],
        id: ProviderID = .appleIntelligence,
        sendsDataExternally: Bool = false,
        requiresNetwork: Bool = false,
        supportsImageAttachments: Bool = false
    ) {
        self.scripts = scripts
        self.id = id
        self.sendsDataExternally = sendsDataExternally
        self.requiresNetwork = requiresNetwork
        self.supportsImageAttachments = supportsImageAttachments
    }

    func generate(_ request: AIRequest) async throws -> AIResponse {
        callCount += 1
        prompts.append(request.prompt)
        lastToolSpecs = request.tools ?? []
        let script = scripts.isEmpty ? .text("") : scripts.removeFirst()
        switch script {
        case .text(let text):
            return AIResponse(
                text: text,
                providerUsed: id,
                tokensUsed: TokenUsage(prompt: 10, completion: 5)
            )
        case .throwing(let error):
            throw error
        case .structured(let text, let toolCalls):
            return AIResponse(
                text: text,
                providerUsed: id,
                tokensUsed: TokenUsage(prompt: 10, completion: 5),
                toolCalls: toolCalls
            )
        }
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }

    func embed(_ request: AIRequest) async throws -> AIResponse {
        AIResponse(text: "", providerUsed: id)
    }
}

struct AllowAllConsentStore: ConsentStore {
    func hasConsent(for provider: ProviderID) async -> Bool { true }
    func setConsent(_ granted: Bool, for provider: ProviderID) async {}
}

extension String {
    func occurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
