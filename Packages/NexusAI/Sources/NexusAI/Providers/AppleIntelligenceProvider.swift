import Foundation
import FoundationModels

/// Apple Intelligence Foundation Models adapter.
///
/// Generation is fulfilled by `LanguageModelSession.respond(to:)`. The provider is
/// the **default** on-device choice for `.generate` per spec §6.3 — when offline,
/// or when a request can be served on-device, the router picks this provider before
/// any cloud option (D5).
///
/// Capabilities deliberately exclude:
/// - `.longContext` — Foundation Models has ~4K-8K token context (per spec §11.4
///   and `SystemLanguageModel.contextSize`).
/// - `.transcribe` — handled by `WhisperKit` (separate on-device provider).
///
/// Provider availability stays true because `.embed` is backed by NaturalLanguage
/// and must route even when Foundation Models generation is unavailable. Generation
/// checks `SystemLanguageModel.default.availability` at call time and reports a
/// provider request failure if the model is unsupported, disabled, or downloading.
public final class AppleIntelligenceProvider: AIProvider {
    private let embeddingImpl: AppleIntelligenceEmbeddingImpl
    private let isFoundationModelAvailable: @Sendable () -> Bool

    public init(
        embeddingImpl: AppleIntelligenceEmbeddingImpl = AppleIntelligenceEmbeddingImpl(),
        isFoundationModelAvailable: @escaping @Sendable () -> Bool = {
            AppleIntelligenceProvider.isModelAvailable
        }
    ) {
        self.embeddingImpl = embeddingImpl
        self.isFoundationModelAvailable = isFoundationModelAvailable
    }

    public let id: ProviderID = .appleIntelligence
    public let capabilities: Set<AICapability> = [.generate, .embed]
    public let sendsDataExternally: Bool = false
    public let requiresNetwork: Bool = false

    public var isAvailableOnThisPlatform: Bool { true }

    /// Stays available for `.embed`/`.transcribe` routing (NaturalLanguage embeddings work even
    /// when Foundation Models generation is off), but only reports ready for `.generate`/
    /// `.longContext` when Foundation Models is actually available. Without this, the router would
    /// always pick this provider for `.generate` (it is `isAvailableOnThisPlatform == true` and
    /// first in the provider list) and then dead-end at invoke on a device without Apple
    /// Intelligence, never falling back to a loaded MLX chat model.
    public func isReady(for capability: AICapability) -> Bool {
        switch capability {
        case .generate, .longContext:
            return isFoundationModelAvailable()
        case .embed, .transcribe:
            return true
        }
    }

    /// Convenience flag for callers (router composition root, settings UI, tests)
    /// to check Apple Intelligence readiness without importing `FoundationModels`.
    public static var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    public func generate(_ request: AIRequest) async throws -> AIResponse {
        guard isFoundationModelAvailable() else {
            throw AIRouterError.requestFailed(
                .appleIntelligence,
                "Foundation Models generation is unavailable on this device."
            )
        }

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: request.prompt)
            return AIResponse(
                text: response.content,
                providerUsed: .appleIntelligence,
                citations: request.context
            )
        } catch let error as LanguageModelSession.GenerationError {
            // Apple's on-device guardrail is known to false-positive on benign,
            // non-English prompts and surfaces a bare "Detected content likely to
            // be unsafe". Replace that with an actionable message that points the
            // user at the real escape hatch: assigning a local MLX chat model
            // (which the router then prefers over Apple Intelligence — see
            // `AIComposition`). Other generation errors keep their own description.
            if case .guardrailViolation = error {
                throw AIRouterError.requestFailed(
                    .appleIntelligence,
                    """
                    Apple Intelligence blocked this request with its on-device safety \
                    filter — this commonly misfires on non-English text. Download and \
                    assign a local model in Settings → Models to handle chat instead.
                    """
                )
            }
            throw AIRouterError.requestFailed(.appleIntelligence, error.localizedDescription)
        }
    }

    public func transcribe(_ request: AIRequest) async throws -> AIResponse {
        throw AIRouterError.providerNotImplemented(.appleIntelligence)
    }

    public func embed(_ text: String) async throws -> [Float] {
        try await embeddingImpl.embed(text, languageCode: nil)
    }

    public func embed(_ request: AIRequest) async throws -> AIResponse {
        let vector = try await embed(request.prompt)
        return AIResponse(
            text: "",
            providerUsed: .appleIntelligence,
            citations: request.context,
            embeddingVector: vector
        )
    }
}
