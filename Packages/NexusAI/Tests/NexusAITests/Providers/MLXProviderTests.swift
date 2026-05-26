import Foundation
import NexusCore
import Testing

@testable import NexusAI

/// Local stub mirroring `StubMLXChat` from `MLXChatEngineTests.swift` (that one
/// is `private` to its file, so it cannot be reused here). Records the inputs
/// the engine forwards so the provider's message-assembly and tool-spec
/// conversion can be asserted against real engine inputs, and supports a
/// mid-stream failure for the rethrow test.
private final class StubMLXChat: MLXChatGenerating, @unchecked Sendable {
    let cannedChunks: [MLXChunk]
    let failure: Error?
    private(set) var lastMessages: [MLXChatMessage] = []
    private(set) var lastTools: [MLXToolSpec] = []

    init(cannedChunks: [MLXChunk], failure: Error? = nil) {
        self.cannedChunks = cannedChunks
        self.failure = failure
    }

    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        lastMessages = messages
        lastTools = tools
        let chunks = cannedChunks
        let fail = failure
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            if let fail {
                continuation.finish(throwing: fail)
            } else {
                continuation.finish()
            }
        }
    }

    func unload() async {}
}

private struct Boom: Error {}

private func makeEngine(_ stub: StubMLXChat) -> MLXChatEngine {
    MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in stub }
}

@Suite("MLXProvider")
struct MLXProviderTests {
    @Test("plain query concatenates text and reports the mlx provider")
    func plainQueryConcatenatesText() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("Hello, "), .text("world"), .text("!")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        let response = try await provider.generate(
            AIRequest(prompt: "hi", capability: .generate)
        )

        #expect(response.text == "Hello, world!")
        #expect(response.providerUsed == .mlx)
        #expect(response.toolCalls.isEmpty)
        #expect(response.costEstimateUSD == 0)
    }

    @Test("a tool-call chunk surfaces a decoded AIToolCall")
    func toolCallChunkSurfacesAIToolCall() async throws {
        let stub = StubMLXChat(cannedChunks: [
            .toolCall(name: "tasks.create", arguments: #"{"title":"Buy milk"}"#)
        ])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        let response = try await provider.generate(
            AIRequest(prompt: "add a task", capability: .generate)
        )

        #expect(response.toolCalls.count == 1)
        let call = try #require(response.toolCalls.first)
        #expect(call.name == "tasks.create")
        #expect(call.arguments["title"]?.stringValue == "Buy milk")
    }

    @Test("an info chunk populates tokensUsed")
    func infoChunkPopulatesTokenUsage() async throws {
        let stub = StubMLXChat(cannedChunks: [
            .text("ok"),
            .info(promptTokens: 42, completionTokens: 7),
        ])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        let response = try await provider.generate(
            AIRequest(prompt: "hi", capability: .generate)
        )

        #expect(response.tokensUsed == TokenUsage(prompt: 42, completion: 7))
    }

    @Test("request.prompt is the final user message even when messages are present")
    func promptIsNotDroppedWhenMessagesPresent() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        let priorMessages: [AIChatMessage] = [
            AIChatMessage(role: .system, text: "be terse"),
            AIChatMessage(role: .assistant, text: "earlier turn"),
        ]
        var request = AIRequest(prompt: "CONTEXT-COMPLETE-USER-TURN", capability: .generate)
        request.systemPrompt = "system instructions"
        request.messages = priorMessages

        _ = try await provider.generate(request)

        // System prompt first, then prior messages, then a FINAL .user message
        // whose text is EXACTLY request.prompt (not concatenated elsewhere).
        #expect(stub.lastMessages.map(\.role) == [.system, .system, .assistant, .user])
        #expect(stub.lastMessages.first?.text == "system instructions")
        // Prior request.messages are forwarded too.
        #expect(stub.lastMessages[1].text == "be terse")
        #expect(stub.lastMessages[2].text == "earlier turn")
        // The context-complete prompt is the last message and is not dropped.
        #expect(stub.lastMessages.last?.role == .user)
        #expect(stub.lastMessages.last?.text == "CONTEXT-COMPLETE-USER-TURN")
    }

    @Test("no systemPrompt and no messages yields a single user message from prompt")
    func bareRequestSendsOnlyPromptUserMessage() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        _ = try await provider.generate(
            AIRequest(prompt: "just the prompt", capability: .generate)
        )

        #expect(stub.lastMessages.count == 1)
        #expect(stub.lastMessages.first?.role == .user)
        #expect(stub.lastMessages.first?.text == "just the prompt")
    }

    @Test("empty request.prompt still produces a final .user message")
    func emptyPromptStillProducesFinalUserMessage() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        // Pins the context-completeness invariant: prompt is never guarded away,
        // even when empty — the engine must always receive a final .user turn.
        _ = try await provider.generate(
            AIRequest(prompt: "", capability: .generate)
        )

        #expect(stub.lastMessages.count == 1)
        #expect(stub.lastMessages.last?.role == .user)
        #expect(stub.lastMessages.last?.text.isEmpty == true)
    }

    @Test("whitespace-only systemPrompt produces no .system message")
    func blankSystemPromptProducesNoSystemMessage() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        var request = AIRequest(prompt: "hi", capability: .generate)
        request.systemPrompt = "   \n\t "

        _ = try await provider.generate(request)

        // A blank systemPrompt must not leak a content-free .system message that
        // could fight the model's chat template.
        #expect(stub.lastMessages.map(\.role) == [.user])
        #expect(stub.lastMessages.last?.text == "hi")
    }

    @Test("no .info chunk leaves tokensUsed at zero")
    func noInfoChunkLeavesTokensUsedZero() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("hello"), .text(" world")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        let response = try await provider.generate(
            AIRequest(prompt: "hi", capability: .generate)
        )

        #expect(response.text == "hello world")
        #expect(response.tokensUsed == .zero)
    }

    @Test("request.tools is converted and forwarded to the engine")
    func toolsAreConvertedAndForwarded() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        var request = AIRequest(prompt: "do it", capability: .generate)
        request.tools = [
            AIToolSpec(
                name: "tasks.create",
                description: "Create a task",
                parametersJSONSchema: #"{"type":"object","properties":{"title":{"type":"string"}}}"#
            )
        ]

        _ = try await provider.generate(request)

        #expect(stub.lastTools.count == 1)
        let forwarded = try #require(stub.lastTools.first)
        #expect(forwarded.name == "tasks.create")
        #expect(forwarded.description == "Create a task")
        #expect(
            forwarded.parametersJSONSchema
                == #"{"type":"object","properties":{"title":{"type":"string"}}}"#
        )
    }

    @Test("nil tools yields an empty tool list (plain generation)")
    func nilToolsYieldsEmptyToolList() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        _ = try await provider.generate(
            AIRequest(prompt: "hi", capability: .generate)
        )

        #expect(stub.lastTools.isEmpty)
    }

    @Test("availabilityProbe drives isAvailableOnThisPlatform")
    func availabilityProbeDrivesAvailability() {
        let stub = StubMLXChat(cannedChunks: [])
        let unavailable = MLXProvider(engine: makeEngine(stub), availabilityProbe: { false })
        let available = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        #expect(unavailable.isAvailableOnThisPlatform == false)
        #expect(available.isAvailableOnThisPlatform == true)
    }

    @Test("a mid-stream error is rethrown, not swallowed")
    func midStreamErrorIsRethrown() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("partial")], failure: Boom())
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        await #expect(throws: Boom.self) {
            _ = try await provider.generate(
                AIRequest(prompt: "hi", capability: .generate)
            )
        }
    }

    @Test("transcribe throws the shared unsupported-capability error")
    func transcribeThrowsProviderNotImplemented() async throws {
        let stub = StubMLXChat(cannedChunks: [])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        await #expect(throws: AIRouterError.providerNotImplemented(.mlx)) {
            _ = try await provider.transcribe(
                AIRequest(prompt: "x", capability: .transcribe)
            )
        }
    }

    @Test("embed throws the shared unsupported-capability error")
    func embedThrowsProviderNotImplemented() async throws {
        let stub = StubMLXChat(cannedChunks: [])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        await #expect(throws: AIRouterError.providerNotImplemented(.mlx)) {
            _ = try await provider.embed(
                AIRequest(prompt: "x", capability: .embed)
            )
        }
    }
}
