import Foundation
import Testing

@testable import NexusAgent

@Suite struct NLEmbeddingClientTests {
    @Test func polishTextReturns512DimensionVectorAndContractLanguage() throws {
        let client = NLEmbeddingClient()
        let result = try embedOrFailIfModelUnavailable(client, text: "To jest testowe zdanie po polsku.")

        #expect(result.dimension == NLEmbeddingClient.requiredDimension)
        #expect(result.vector.count == NLEmbeddingClient.requiredDimension * MemoryLayout<Float>.size)
        #expect(["pl", "en", "multilingual"].contains(result.detectedLanguage))
    }

    @Test func numericTextFallsBackToMultilingualAnd512DimensionVector() throws {
        let client = NLEmbeddingClient()
        let result = try embedOrFailIfModelUnavailable(client, text: "12345 67890")

        #expect(result.dimension == NLEmbeddingClient.requiredDimension)
        #expect(result.vector.count == NLEmbeddingClient.requiredDimension * MemoryLayout<Float>.size)
        #expect(result.detectedLanguage == "multilingual")
    }

    @Test func unsupportedLanguageNormalizesToMultilingual() throws {
        let language = try NLEmbeddingClient.normalizedDetectedLanguage(
            for: "Bonjour, je dois préparer le déjeuner demain."
        )

        #expect(language == "multilingual")
    }

    @Test func sameNormalizedTrimmedTextHashIsStableAndDifferentTextDiffers() throws {
        let client = NLEmbeddingClient()
        let r1 = try embedOrFailIfModelUnavailable(client, text: "hello world")
        let r2 = try embedOrFailIfModelUnavailable(client, text: "  hello world\n")
        let r3 = try embedOrFailIfModelUnavailable(client, text: "hello nexus")

        #expect(r1.textHash == r2.textHash)
        #expect(r1.textHash != r3.textHash)
    }

    @Test func hashUsesCanonicalUnicodeNormalization() throws {
        let precomposed = try NLEmbeddingClient.normalizedTextHash(for: "Café")
        let decomposed = try NLEmbeddingClient.normalizedTextHash(for: "Cafe\u{301}")

        #expect(precomposed == decomposed)
    }

    @Test func helloWorldHashMatchesKnownSHA256OfNormalizedTrimmedText() throws {
        let hash = try NLEmbeddingClient.normalizedTextHash(for: "  hello world\n")

        #expect(hash == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test func emptyTextThrows() throws {
        let client = NLEmbeddingClient()

        #expect(throws: NLEmbeddingError.emptyText) {
            try client.embed(" \n\t ")
        }
    }

    @Test func unavailable512ModelReportsExactError() throws {
        let client = NLEmbeddingClient(
            multilingualModel: nil,
            englishModel: nil,
            usesLanguageSpecificFallbacks: false
        )

        #expect(throws: NLEmbeddingError.modelUnavailable(language: "multilingual")) {
            try client.embed("Bonjour, je dois préparer le déjeuner demain.")
        }
    }

    @Test func lowSignalTextMayUseZeroVectorButKeeps512DimensionContract() throws {
        let client = NLEmbeddingClient()
        let result = try embedOrFailIfModelUnavailable(client, text: "12345")

        #expect(result.dimension == NLEmbeddingClient.requiredDimension)
        #expect(result.vector.count == NLEmbeddingClient.requiredDimension * MemoryLayout<Float>.size)
    }

    @Test func concurrentCallsOnSharedClientRemainStable() async throws {
        let client = NLEmbeddingClient()
        let texts = [
            "Prepare the project review for tomorrow morning.",
            "Zaplanuj spokojny blok pracy nad aplikacją.",
            "Check calendar conflicts and summarize the day.",
            "Dodaj zadanie z krótkim terminem na dziś.",
        ]

        try await withThrowingTaskGroup(of: NLEmbeddingResult.self) { group in
            for index in 0..<32 {
                let text = texts[index % texts.count]
                group.addTask {
                    try embedOrFailIfModelUnavailable(client, text: "\(text) \(index)")
                }
            }

            var count = 0
            for try await result in group {
                #expect(result.dimension == NLEmbeddingClient.requiredDimension)
                #expect(result.vector.count == NLEmbeddingClient.requiredDimension * MemoryLayout<Float>.size)
                count += 1
            }

            #expect(count == 32)
        }
    }
}

private func embedOrFailIfModelUnavailable(
    _ client: NLEmbeddingClient,
    text: String
) throws -> NLEmbeddingResult {
    do {
        return try client.embed(text)
    } catch let error as NLEmbeddingError {
        if case .modelUnavailable(let language) = error {
            Issue.record(
                """
                Expected a 512-dim local NLEmbedding model on this development target; \
                got modelUnavailable(language: \(language)).
                """
            )
        }
        throw error
    }
}
