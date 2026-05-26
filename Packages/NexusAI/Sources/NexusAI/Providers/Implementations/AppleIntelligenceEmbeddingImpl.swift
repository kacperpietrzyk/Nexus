import Foundation
import NaturalLanguage

public final class AppleIntelligenceEmbeddingImpl: Sendable {
    /// Stable vector width for Phase 1k semantic consumers. NLEmbedding can expose
    /// different widths across model families, so this adapter pads/truncates.
    public static let vectorDimension = 512

    public init() {}

    public func embed(_ text: String, languageCode: String?) async throws -> [Float] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping

        guard !normalized.isEmpty else {
            throw AIRouterError.requestFailed(
                .appleIntelligence,
                "Embedding input is empty."
            )
        }

        if let vector = try await foundationModelsEmbed(text: normalized) {
            return Self.normalizeDimension(vector)
        }

        let language = resolvedLanguageCode(languageCode)
        var sawEmbeddingModel = false

        for candidate in embeddingCandidates(for: language) {
            guard let embedding = candidate.embedding else { continue }
            sawEmbeddingModel = true

            if let vector = embedding.vector(for: normalized) {
                return Self.normalizeDimension(vector.map(Float.init))
            }
        }

        if sawEmbeddingModel {
            throw AIRouterError.requestFailed(
                .appleIntelligence,
                "NLEmbedding returned no vector for the request."
            )
        }

        throw AIRouterError.providerNotImplemented(.appleIntelligence)
    }

    private func foundationModelsEmbed(text: String) async throws -> [Float]? {
        #if canImport(FoundationModels)
        _ = text
        return nil
        #else
        _ = text
        return nil
        #endif
    }

    private func resolvedLanguageCode(_ languageCode: String?) -> String {
        if let languageCode {
            return normalizedLanguageCode(languageCode) ?? "en"
        }

        let localeLanguage = Locale.current.language.languageCode?.identifier
        if let language = normalizedLanguageCode(localeLanguage) {
            return language
        }

        return "en"
    }

    private func normalizedLanguageCode(_ code: String?) -> String? {
        guard let code else { return nil }

        let language = code.split(separator: "-").first
            .map(String.init)?
            .lowercased()

        guard let language, Self.supportedLanguageCodes.contains(language) else {
            return nil
        }

        return language
    }

    private func embeddingCandidates(
        for languageCode: String
    ) -> [(embedding: NLEmbedding?, language: NLLanguage)] {
        let primary = nlLanguage(for: languageCode)
        var candidates = [
            (NLEmbedding.sentenceEmbedding(for: primary), primary),
            (NLEmbedding.wordEmbedding(for: primary), primary),
        ]

        if primary != .english {
            candidates.append((NLEmbedding.sentenceEmbedding(for: .english), .english))
            candidates.append((NLEmbedding.wordEmbedding(for: .english), .english))
        }

        return candidates
    }

    private func nlLanguage(for languageCode: String) -> NLLanguage {
        switch languageCode {
        case "pl": return .polish
        case "de": return .german
        case "fr": return .french
        case "es": return .spanish
        case "it": return .italian
        case "pt": return .portuguese
        default: return .english
        }
    }

    private static let supportedLanguageCodes: Set<String> = [
        "pl",
        "en",
        "de",
        "fr",
        "es",
        "it",
        "pt",
    ]

    private static func normalizeDimension(_ vector: [Float]) -> [Float] {
        if vector.count == vectorDimension {
            return vector
        }

        if vector.count > vectorDimension {
            return Array(vector.prefix(vectorDimension))
        }

        return vector + Array(repeating: 0, count: vectorDimension - vector.count)
    }
}
