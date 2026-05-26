import Testing

@testable import NexusAI

@Test func appleEmbedReturnsNonEmptyVectorForEnglish() async throws {
    let impl = AppleIntelligenceEmbeddingImpl()
    let vector = try await impl.embed("hello world", languageCode: "en")
    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleEmbedFallsBackToEnglishForUnknownLocale() async throws {
    let impl = AppleIntelligenceEmbeddingImpl()
    let vector = try await impl.embed("test", languageCode: "xyz-unknown")
    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleEmbedHandlesPolish() async throws {
    let impl = AppleIntelligenceEmbeddingImpl()
    let vector = try await impl.embed("dzień dobry", languageCode: "pl")
    #expect(!vector.isEmpty)
    #expect(vector.count == AppleIntelligenceEmbeddingImpl.vectorDimension)
}

@Test func appleEmbedEmptyInputReportsRequestFailure() async {
    let impl = AppleIntelligenceEmbeddingImpl()

    await #expect(
        throws: AIRouterError.requestFailed(
            .appleIntelligence,
            "Embedding input is empty."
        )
    ) {
        try await impl.embed(" \n\t ", languageCode: "en")
    }
}
