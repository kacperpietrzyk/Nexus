import Foundation
import NexusCore
import Testing

@testable import NexusAI

@Test func aiResponse_capturesProviderAndTokens() {
    let r = AIResponse(
        text: "answer",
        providerUsed: .appleIntelligence,
        citations: [],
        tokensUsed: .init(prompt: 50, completion: 20),
        costEstimateUSD: 0.0
    )
    #expect(r.text == "answer")
    #expect(r.providerUsed == .appleIntelligence)
    #expect(r.embeddingVector == nil)
    #expect(r.tokensUsed.total == 70)
    #expect(r.costEstimateUSD == 0.0)
}

@Test func aiResponse_canCarryEmbeddingVector() {
    let r = AIResponse(
        text: "",
        providerUsed: .appleIntelligence,
        embeddingVector: [0.1, 0.2, 0.3]
    )

    #expect(r.text.isEmpty)
    #expect(r.embeddingVector == [0.1, 0.2, 0.3])
}

@Test func tokenUsage_total_isSumOfPromptAndCompletion() {
    let u = TokenUsage(prompt: 100, completion: 25)
    #expect(u.total == 125)
}

@Test func aiResponse_isCodable_roundTrip() throws {
    let r = AIResponse(
        text: "hello",
        providerUsed: .whisperKit,
        citations: ["item-1"],
        embeddingVector: [0.25, 0.5],
        tokensUsed: .init(prompt: 5, completion: 3),
        costEstimateUSD: 0.0001
    )
    let data = try JSONEncoder().encode(r)
    let back = try JSONDecoder().decode(AIResponse.self, from: data)
    #expect(back == r)
}

@Test func aiResponse_decodesLegacyPayloadWithoutEmbeddingVector() throws {
    let json = """
        {
          "text": "hello",
          "providerUsed": "appleIntelligence",
          "citations": [],
          "tokensUsed": {
            "prompt": 0,
            "completion": 0
          },
          "costEstimateUSD": 0
        }
        """

    let response = try JSONDecoder().decode(AIResponse.self, from: Data(json.utf8))

    #expect(response.text == "hello")
    #expect(response.providerUsed == .appleIntelligence)
    #expect(response.embeddingVector == nil)
}

@Test func aiResponse_toolCalls_defaultsToEmpty() {
    let r = AIResponse(text: "answer", providerUsed: .appleIntelligence)
    #expect(r.toolCalls.isEmpty)
}

@Test func aiResponse_isCodable_roundTrip_withToolCalls() throws {
    let r = AIResponse(
        text: "I'll add the task.",
        providerUsed: .mlx,
        tokensUsed: .init(prompt: 12, completion: 4),
        toolCalls: [
            AIToolCall(
                name: "tasks.create",
                arguments: .object(["title": .string("Buy milk")])
            )
        ]
    )
    let data = try JSONEncoder().encode(r)
    let back = try JSONDecoder().decode(AIResponse.self, from: data)
    #expect(back == r)
    #expect(back.toolCalls.count == 1)
    #expect(back.toolCalls.first?.name == "tasks.create")
    #expect(back.toolCalls.first?.arguments == .object(["title": .string("Buy milk")]))
}

@Test func aiResponse_decodesLegacyPayloadWithoutToolCalls() throws {
    let json = """
        {
          "text": "hello",
          "providerUsed": "appleIntelligence",
          "citations": [],
          "tokensUsed": {
            "prompt": 0,
            "completion": 0
          },
          "costEstimateUSD": 0
        }
        """

    let response = try JSONDecoder().decode(AIResponse.self, from: Data(json.utf8))

    #expect(response.toolCalls.isEmpty)
}
