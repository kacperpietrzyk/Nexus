import Foundation

/// Token usage reported by a provider. `prompt` + `completion` separated so cost
/// math (different rates per side on most cloud providers) stays accurate when
/// `AIUsageLog` lands in Phase 0f.
public struct TokenUsage: Sendable, Codable, Equatable {
    public var prompt: Int
    public var completion: Int
    public init(prompt: Int, completion: Int) {
        self.prompt = prompt
        self.completion = completion
    }
    public var total: Int { prompt + completion }

    public static let zero = TokenUsage(prompt: 0, completion: 0)
}

/// Result of one AI call. `providerUsed` is what the router actually picked
/// (may differ from `request.providerPreference == .auto`). `costEstimateUSD == 0`
/// for on-device providers. `citations` are opaque IDs echoing `AIRequest.context`
/// the provider could ground its output in — the UI uses them for backlinks.
///
/// `toolCalls` is populated by providers that support native structured tool-calling
/// (e.g. MLX). `AgentRuntime` checks this field first; if non-empty it routes directly
/// to `ToolDispatcher` without JSON text-envelope parsing. Defaults to `[]` so old
/// persisted JSON (which has no `toolCalls` key) decodes without error.
public struct AIResponse: Sendable, Codable, Equatable {
    public var text: String
    public var providerUsed: ProviderID
    public var citations: [String]
    public var embeddingVector: [Float]?
    public var tokensUsed: TokenUsage
    public var costEstimateUSD: Double
    /// Structured tool calls returned by the provider. Empty for text-only responses.
    public var toolCalls: [AIToolCall]

    public init(
        text: String,
        providerUsed: ProviderID,
        citations: [String] = [],
        embeddingVector: [Float]? = nil,
        tokensUsed: TokenUsage = .zero,
        costEstimateUSD: Double = 0.0,
        toolCalls: [AIToolCall] = []
    ) {
        self.text = text
        self.providerUsed = providerUsed
        self.citations = citations
        self.embeddingVector = embeddingVector
        self.tokensUsed = tokensUsed
        self.costEstimateUSD = costEstimateUSD
        self.toolCalls = toolCalls
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case text, providerUsed, citations, embeddingVector, tokensUsed, costEstimateUSD
        case toolCalls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        providerUsed = try c.decode(ProviderID.self, forKey: .providerUsed)
        citations = try c.decode([String].self, forKey: .citations)
        embeddingVector = try c.decodeIfPresent([Float].self, forKey: .embeddingVector)
        tokensUsed = try c.decode(TokenUsage.self, forKey: .tokensUsed)
        costEstimateUSD = try c.decode(Double.self, forKey: .costEstimateUSD)
        // Old persisted JSON has no `toolCalls` key — default to empty array.
        toolCalls = try c.decodeIfPresent([AIToolCall].self, forKey: .toolCalls) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(providerUsed, forKey: .providerUsed)
        try c.encode(citations, forKey: .citations)
        try c.encodeIfPresent(embeddingVector, forKey: .embeddingVector)
        try c.encode(tokensUsed, forKey: .tokensUsed)
        try c.encode(costEstimateUSD, forKey: .costEstimateUSD)
        try c.encode(toolCalls, forKey: .toolCalls)
    }
}
