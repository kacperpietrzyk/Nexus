import CryptoKit
import Foundation
import NaturalLanguage

public struct NLEmbeddingResult: Sendable {
    public let vector: Data
    public let detectedLanguage: String
    public let textHash: String
    public let dimension: Int

    public init(vector: Data, detectedLanguage: String, textHash: String, dimension: Int) {
        self.vector = vector
        self.detectedLanguage = detectedLanguage
        self.textHash = textHash
        self.dimension = dimension
    }
}

public enum NLEmbeddingError: Error, Equatable, Sendable {
    case emptyText
    case modelUnavailable(language: String)
}

public final class NLEmbeddingClient {
    public static let requiredDimension = 512

    private let multilingualModel: NLEmbedding?
    private let englishModel: NLEmbedding?
    private let usesLanguageSpecificFallbacks: Bool
    private let embeddingLock = NSLock()

    public init() {
        self.multilingualModel = NLEmbedding.sentenceEmbedding(for: .undetermined)
        self.englishModel = NLEmbedding.sentenceEmbedding(for: .english)
        self.usesLanguageSpecificFallbacks = true
    }

    init(
        multilingualModel: NLEmbedding?,
        englishModel: NLEmbedding?,
        usesLanguageSpecificFallbacks: Bool = true
    ) {
        self.multilingualModel = multilingualModel
        self.englishModel = englishModel
        self.usesLanguageSpecificFallbacks = usesLanguageSpecificFallbacks
    }

    public func embed(_ text: String) throws -> NLEmbeddingResult {
        let normalized = try Self.normalizedInput(for: text)
        let language = Self.detectLanguage(of: normalized)

        return try embeddingLock.withLock {
            guard let model = model(for: language) else {
                throw NLEmbeddingError.modelUnavailable(language: language)
            }

            let vector = model.vector(for: normalized) ?? Self.zeroVector(dimension: model.dimension)
            let floats = vector.map(Float.init)
            let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }

            return NLEmbeddingResult(
                vector: data,
                detectedLanguage: language,
                textHash: Self.hash(of: normalized),
                dimension: model.dimension
            )
        }
    }

    static func normalizedTextHash(for text: String) throws -> String {
        try hash(of: normalizedInput(for: text))
    }

    static func normalizedDetectedLanguage(for text: String) throws -> String {
        try detectLanguage(of: normalizedInput(for: text))
    }

    private func model(for language: String) -> NLEmbedding? {
        for model in candidateModels(for: language) where model.dimension == Self.requiredDimension {
            return model
        }

        return nil
    }

    private func candidateModels(for language: String) -> [NLEmbedding] {
        var models = [NLEmbedding]()

        if let multilingualModel {
            models.append(multilingualModel)
        }

        if usesLanguageSpecificFallbacks, language == "pl" || language == "en" {
            if let languageModel = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: language)) {
                models.append(languageModel)
            }
        }

        if let englishModel {
            models.append(englishModel)
        }

        return models
    }

    private static func detectLanguage(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        switch recognizer.dominantLanguage {
        case .polish:
            return "pl"
        case .english:
            return "en"
        case .undetermined, nil:
            return "multilingual"
        default:
            return "multilingual"
        }
    }

    private static func normalizedInput(for text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.precomposedStringWithCanonicalMapping

        guard !normalized.isEmpty else {
            throw NLEmbeddingError.emptyText
        }

        return normalized
    }

    private static func hash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func zeroVector(dimension: Int) -> [Double] {
        // NLEmbedding can report a model but decline a vector for low-signal input.
        // Preserve model dimensionality so downstream vector storage stays valid.
        Array(repeating: 0, count: dimension)
    }
}

extension NLEmbeddingClient: @unchecked Sendable {}
