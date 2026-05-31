import Foundation

// MARK: - For testing only
//
// Configurable provider that succeeds with a canned `AIResponse` (or fails with a
// canned error) whenever it's invoked. Tests use this to verify routing decisions
// without writing 4 different real providers — the router's job is *picking*, and
// `FakeAIProvider` lets a test assert "router picked the provider with id .foo"
// by setting that provider's `responseText` and reading `AIResponse.providerUsed`.

public final class FakeAIProvider: AIProvider, @unchecked Sendable {
    public let id: ProviderID
    public let capabilities: Set<AICapability>
    public let sendsDataExternally: Bool
    public let requiresNetwork: Bool
    public let isAvailableOnThisPlatform: Bool
    public let supportsImageAttachments: Bool
    /// Capabilities this fake is NOT ready to serve (simulates e.g. Apple Intelligence
    /// generation being unavailable while embeddings still route). Empty = ready for all.
    public let unreadyCapabilities: Set<AICapability>

    /// What `generate/transcribe/embed` returns. Defaults to a canned response
    /// stamping `providerUsed = self.id` so routing assertions are trivial.
    public var responseText: String
    public var tokensUsed: TokenUsage
    public var costEstimateUSD: Double
    public var errorToThrow: AIRouterError?

    /// Counts how many times each method was called. Tests assert on this
    /// to confirm gates (consent, quota) blocked invocation when expected.
    public var generateCallCount: Int = 0
    public var transcribeCallCount: Int = 0
    public var embedCallCount: Int = 0

    public init(
        id: ProviderID,
        capabilities: Set<AICapability> = [.generate],
        sendsDataExternally: Bool = false,
        requiresNetwork: Bool = false,
        isAvailableOnThisPlatform: Bool = true,
        supportsImageAttachments: Bool = false,
        unreadyCapabilities: Set<AICapability> = [],
        responseText: String = "fake response",
        tokensUsed: TokenUsage = .init(prompt: 1, completion: 1),
        costEstimateUSD: Double = 0.0,
        errorToThrow: AIRouterError? = nil
    ) {
        self.id = id
        self.capabilities = capabilities
        self.sendsDataExternally = sendsDataExternally
        self.requiresNetwork = requiresNetwork
        self.isAvailableOnThisPlatform = isAvailableOnThisPlatform
        self.supportsImageAttachments = supportsImageAttachments
        self.unreadyCapabilities = unreadyCapabilities
        self.responseText = responseText
        self.tokensUsed = tokensUsed
        self.costEstimateUSD = costEstimateUSD
        self.errorToThrow = errorToThrow
    }

    public func isReady(for capability: AICapability) -> Bool {
        !unreadyCapabilities.contains(capability)
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        generateCallCount += 1
        if let e = errorToThrow { throw e }
        return AIResponse(
            text: responseText,
            providerUsed: id,
            citations: request.context,
            tokensUsed: tokensUsed,
            costEstimateUSD: costEstimateUSD
        )
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        transcribeCallCount += 1
        if let e = errorToThrow { throw e }
        return AIResponse(text: responseText, providerUsed: id, tokensUsed: tokensUsed, costEstimateUSD: costEstimateUSD)
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        embedCallCount += 1
        if let e = errorToThrow { throw e }
        return AIResponse(text: responseText, providerUsed: id, tokensUsed: tokensUsed, costEstimateUSD: costEstimateUSD)
    }
}
