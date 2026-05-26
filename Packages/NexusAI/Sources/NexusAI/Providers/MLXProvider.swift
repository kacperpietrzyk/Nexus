import Foundation

/// On-device language-model provider backed by `MLXChatEngine`.
///
/// `MLXProvider` only advertises `.generate`. It is on-device (no consent, no
/// network) and surfaces *structured* tool calls — it does NOT dispatch tools,
/// loop on tool calls, or use `ChatSession`. `AgentRuntime` (Task 10.5
/// structured-first dispatch) owns the actual tool execution, audit, and undo;
/// this provider just folds engine output into `AIResponse.toolCalls`.
///
/// ## Context completeness
///
/// `AIRequest.messages` / `AIRequest.systemPrompt` are NOT context-complete.
/// `AgentRuntime.makeAIRequest` folds the memory section, RAG hits, and the
/// ephemeral context prefix ONLY into the flat `AIRequest.prompt`, never into
/// `messages`/`systemPrompt`. Therefore the final user-turn content handed to
/// the model MUST be `request.prompt`. The message list is assembled as:
///
/// 1. an optional `.system` message from `request.systemPrompt` (only when
///    non-nil and non-blank — no invented default that could fight the model's
///    own chat template),
/// 2. any `request.messages` prior turns (converted via `MLXChatConverters`),
/// 3. a FINAL `.user` message whose text is exactly `request.prompt`.
///
/// Dropping `request.prompt` while forwarding `request.messages` would be a
/// silent context regression.
public actor MLXProvider: AIProvider {
    public nonisolated let id: ProviderID = .mlx
    public nonisolated let capabilities: Set<AICapability> = [.generate]
    public nonisolated let sendsDataExternally: Bool = false
    public nonisolated let requiresNetwork: Bool = false
    // OCR pipeline handles images in a later task; the model itself is text-only.
    public nonisolated let supportsImageAttachments: Bool = false

    public nonisolated var isAvailableOnThisPlatform: Bool { availabilityProbe() }

    private nonisolated let availabilityProbe: @Sendable () -> Bool
    private let engine: MLXChatEngine

    public init(
        engine: MLXChatEngine,
        availabilityProbe: @escaping @Sendable () -> Bool
    ) {
        self.engine = engine
        self.availabilityProbe = availabilityProbe
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        var messages: [MLXChatMessage] = []

        let systemPrompt = request.systemPrompt ?? ""
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(MLXChatMessage(role: .system, text: systemPrompt))
        }

        if let priorMessages = request.messages {
            messages.append(contentsOf: MLXChatConverters.mlxChatMessages(from: priorMessages))
        }

        // `request.prompt` is the context-complete user-turn carrier (memory +
        // RAG + ephemeral prefix are folded here, NOT into messages/systemPrompt).
        messages.append(MLXChatMessage(role: .user, text: request.prompt))

        // nil tools ⇒ empty ⇒ plain generation (correct for non-agent callers
        // such as TaskAssist).
        let tools = MLXChatConverters.mlxToolSpecs(from: request.tools ?? [])

        // `AIRequest` exposes no sampling options; use the engine defaults.
        let stream = try await engine.generate(
            messages: messages,
            tools: tools,
            params: .default
        )

        var text = ""
        var toolCalls: [AIToolCall] = []
        var tokensUsed: TokenUsage = .zero

        // A thrown stream error propagates straight out of `generate` — never
        // swallowed.
        for try await chunk in stream {
            switch chunk {
            case .text(let value):
                text += value
            case .toolCall(let name, let arguments):
                toolCalls.append(
                    MLXChatConverters.aiToolCall(name: name, arguments: arguments)
                )
            case .info(let promptTokens, let completionTokens):
                // Last .info wins; the engine emits final cumulative token counts.
                tokensUsed = TokenUsage(prompt: promptTokens, completion: completionTokens)
            }
        }

        return AIResponse(
            text: text,
            providerUsed: .mlx,
            citations: request.context,
            tokensUsed: tokensUsed,
            costEstimateUSD: 0,
            toolCalls: toolCalls
        )
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.mlx)
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.mlx)
    }

    /// Warms the chat container so `isAvailableOnThisPlatform` flips true
    /// without routing a synthetic generate request. This is the entry point
    /// that breaks the availability/load cycle: the engine's `markChatLoaded()`
    /// fires here, bypassing the router's availability filter that would
    /// otherwise never let a cold MLX provider run.
    public func preload() async throws {
        try await engine.preload()
    }

    /// In-process rebind after a model assignment change: drop the stale
    /// container (bumps the engine epoch and clears the lifecycle slot), then
    /// warm again. The engine re-resolves the folder dynamically at load time,
    /// so the reload targets the newly-assigned model.
    public func reload() async throws {
        await engine.unload()
        try await engine.preload()
    }
}
