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

/// Generator whose stream never yields and never finishes — models a wedged
/// `MLX.eval` that blocks the engine forever (and holds its busy gate).
private final class HangingMLXChat: MLXChatGenerating, @unchecked Sendable {
    func generate(
        messages: [MLXChatMessage],
        tools: [MLXToolSpec],
        params: MLXGenerateParameters
    ) async throws -> AsyncThrowingStream<MLXChunk, Error> {
        AsyncThrowingStream { _ in
            // Intentionally retain the continuation without ever resuming it.
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

    @Test("structured messages drive the turns; the flat prompt is NOT a trailing user turn")
    func flatPromptIsNotAppendedWhenStructuredMessagesPresent() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        // The agent path (AgentRuntime.makeAIRequest) sets `messages` to the real
        // conversation, ending with the CURRENT user question, and folds memory/RAG
        // context into `systemPrompt`. The flat `prompt` is the Apple/Whisper carrier
        // and MUST NOT be re-fed here — doing so duplicates the transcript and makes
        // the model echo `user:` / invent `Nexus Assistant:` turns.
        let priorMessages: [AIChatMessage] = [
            AIChatMessage(role: .user, text: "earlier question"),
            AIChatMessage(role: .assistant, text: "earlier reply"),
            AIChatMessage(role: .user, text: "Jakie mam jutro spotkania?"),
        ]
        var request = AIRequest(prompt: "FLAT-TRANSCRIPT-BLOB-MUST-NOT-APPEAR", capability: .generate)
        request.systemPrompt = "You are Nexus Assistant.\n\nMemory:\n(none)"
        request.messages = priorMessages

        _ = try await provider.generate(request)

        // system, then the three structured turns — and nothing else.
        #expect(stub.lastMessages.map(\.role) == [.system, .user, .assistant, .user])
        #expect(stub.lastMessages.first?.role == .system)
        // The FINAL turn is the current user question, not the flat prompt.
        #expect(stub.lastMessages.last?.role == .user)
        #expect(stub.lastMessages.last?.text == "Jakie mam jutro spotkania?")
        // The flat prompt appears nowhere in the message list.
        #expect(stub.lastMessages.contains { $0.text.contains("FLAT-TRANSCRIPT-BLOB") } == false)
    }

    @Test("mid tool-loop: a trailing .tool turn is the final turn, not the flat prompt")
    func toolTurnIsFinalTurnNotFlatPrompt() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        // Inside the agent tool loop, `messages` ends with a `.tool` result and there
        // is no fresh user turn. The flat prompt must still not be appended.
        let loopMessages: [AIChatMessage] = [
            AIChatMessage(role: .user, text: "add a task"),
            AIChatMessage(role: .assistant, text: "calling tool"),
            AIChatMessage(role: .tool, text: #"{"ok":true}"#),
        ]
        var request = AIRequest(prompt: "FLAT-BLOB", capability: .generate)
        request.systemPrompt = "sys"
        request.messages = loopMessages

        _ = try await provider.generate(request)

        #expect(stub.lastMessages.map(\.role) == [.system, .user, .assistant, .tool])
        #expect(stub.lastMessages.last?.role == .tool)
        #expect(stub.lastMessages.contains { $0.text.contains("FLAT-BLOB") } == false)
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

    @Test("recreateEngine abandons a wedged engine so the next generate succeeds")
    func recreateEngineAbandonsWedgedEngineAndNextGenerateSucceeds() async throws {
        // The initial engine's generator hangs forever (mimics a wedged MLX.eval
        // holding the busy gate); the factory builds engines whose generator works.
        let hangingEngine = MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
            HangingMLXChat()
        }
        let engineFactory: @Sendable () -> MLXChatEngine = {
            MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
                StubMLXChat(cannedChunks: [.text("recovered")])
            }
        }
        let provider = MLXProvider(
            engine: hangingEngine,
            availabilityProbe: { true },
            engineFactory: engineFactory
        )

        // Fire the wedged turn and abandon it (never awaited to completion).
        let wedged = Task {
            try await provider.generate(AIRequest(prompt: "hang", capability: .generate))
        }
        // Give the wedged turn a moment to take the busy gate on the old engine.
        try await Task.sleep(for: .milliseconds(50))

        // Abandon the wedged engine and swap in a fresh one.
        await provider.recreateEngine()

        // The NEXT generate must succeed on the fresh engine — the clause that
        // actually proves ABANDON (a reset-in-place would jam behind the gate).
        let response = try await provider.generate(
            AIRequest(prompt: "again", capability: .generate)
        )
        #expect(response.text == "recovered")

        wedged.cancel()
    }

    @Test("recreateEngine clears the stale lifecycle slot so the fresh engine re-warms")
    func recreateEngineClearsStaleLifecycleAvailability() async throws {
        // A real lifecycle marked loaded (as a completed first load would leave it).
        let lifecycle = MLXLifecycleController(
            modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "nexus-mlxprov-recreate", directoryHint: .isDirectory),
            localStateStore: ModelManifestLocalState.Store(),
            initiallyForeground: true,
            startSweep: false
        )
        lifecycle.markChatLoaded()
        #expect(lifecycle.isChatAvailable == true)

        let provider = MLXProvider(
            engine: MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
                HangingMLXChat()
            },
            availabilityProbe: { lifecycle.isChatAvailable },
            engineFactory: {
                MLXChatEngine(folder: URL(fileURLWithPath: "/dev/null")) { _, _ in
                    StubMLXChat(cannedChunks: [.text("ok")])
                }
            },
            resetLifecycleSlot: { lifecycle.unloadChat() }
        )

        await provider.recreateEngine()

        // Availability must flip false: otherwise the app's `!isChatAvailable`-guarded
        // warm would skip, and the cold fresh engine would silently load inside generate.
        #expect(lifecycle.isChatAvailable == false)
    }

    @Test("recreateEngine is a no-op when no engineFactory was injected")
    func recreateEngineIsNoOpWithoutFactory() async throws {
        let stub = StubMLXChat(cannedChunks: [.text("ok")])
        let provider = MLXProvider(engine: makeEngine(stub), availabilityProbe: { true })

        await provider.recreateEngine()

        let response = try await provider.generate(
            AIRequest(prompt: "hi", capability: .generate)
        )
        #expect(response.text == "ok")
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
