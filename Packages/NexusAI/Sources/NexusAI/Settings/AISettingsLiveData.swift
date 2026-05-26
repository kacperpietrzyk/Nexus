import Foundation
import NaturalLanguage
import Observation

public enum AvailabilityState: Equatable, Sendable {
    case available
    case unavailable(reason: UnavailableReason)

    public enum UnavailableReason: String, Sendable {
        case modelNotAvailable
        case modelDownloading
        case userDisabled
    }
}

/// Read-only Settings facade for local provider availability in `AISettingsSection`.
/// Refreshed manually by the view's `.task` modifier on appear.
@MainActor
@Observable
public final class AISettingsLiveData {

    public var appleIntelligenceAvailability: AvailabilityState
    public var embeddingAvailability: AvailabilityState
    public var whisperKitAvailability: AvailabilityState

    public init(router: AIRouter?) {
        _ = router
        self.appleIntelligenceAvailability =
            AppleIntelligenceProvider.isModelAvailable
            ? .available
            : .unavailable(reason: .modelNotAvailable)
        self.embeddingAvailability =
            Self.hasAgentSemanticIndexEmbedding
            ? .available
            : .unavailable(reason: .modelNotAvailable)
        self.whisperKitAvailability =
            WhisperKitProvider().isAvailableOnThisPlatform
            ? .available
            : .unavailable(reason: .modelNotAvailable)
    }

    /// Re-evaluates local provider availability; call from a `.task` modifier,
    /// not from view init.
    public func refresh() async {
        // Re-evaluate availability (may have changed since init).
        // TODO(phase-1b): also produce .modelDownloading and .userDisabled when
        // SystemLanguageModel.availability surfaces those reasons explicitly.
        self.appleIntelligenceAvailability =
            AppleIntelligenceProvider.isModelAvailable
            ? .available
            : .unavailable(reason: .modelNotAvailable)
        self.embeddingAvailability =
            Self.hasAgentSemanticIndexEmbedding
            ? .available
            : .unavailable(reason: .modelNotAvailable)
        self.whisperKitAvailability =
            WhisperKitProvider().isAvailableOnThisPlatform
            ? .available
            : .unavailable(reason: .modelNotAvailable)
    }

    static var hasAgentSemanticIndexEmbedding: Bool {
        NLEmbedding.sentenceEmbedding(for: .english)?.dimension == 512
    }
}
