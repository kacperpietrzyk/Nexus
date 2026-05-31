import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite(.serialized)
struct AgentRuntimeTurnLoopTests {
    @Test
    func runtimeRespondsToSimpleTurn() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("Czesc! Jak moge pomoc?")]
        )
        let threadID = try harness.threadStore.create(title: "smoke")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "hej", scope: "global")
        )

        #expect(response.finalAssistantContent == "Czesc! Jak moge pomoc?")
        #expect(response.haltReason == .completed)
        #expect(response.toolCallsExecuted == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .agent])
        #expect(stored.map(\.content) == ["hej", "Czesc! Jak moge pomoc?"])
        #expect(stored.last?.providerID == ProviderID.appleIntelligence.rawValue)
    }

    @Test
    func removedClaudeProviderHintsFallBackToAppleIntelligence() async throws {
        for providerHint in ["claude", "claude" + "shell"] {
            let harness = try RuntimeHarness.make(
                tools: [],
                scripts: [.text("Apple fallback")]
            )
            let threadID = try harness.threadStore.create(title: "provider-\(providerHint)")

            let response = try await harness.runtime.runTurn(
                AgentTurnRequest(
                    threadID: threadID,
                    userMessage: "hej",
                    scope: "global",
                    providerHint: providerHint
                )
            )

            #expect(response.finalAssistantContent == "Apple fallback")
            #expect(response.haltReason == .completed)
            #expect(harness.provider.callCount == 1)

            let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
            #expect(stored.last?.providerID == ProviderID.appleIntelligence.rawValue)
        }
    }

    @Test
    func runtimeRejectsImageAttachmentsBeforePersistingWhenRouteUnavailable() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("should not be called")]
        )
        let threadID = try harness.threadStore.create(title: "image")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "co tu jest",
                attachments: ["data:image/png;base64,cG5n"],
                scope: "global"
            )
        )

        #expect(response.finalAssistantContent == nil)
        #expect(
            response.haltReason
                == .providerError("Image attachments arrive with on-device AI in the next phase.")
        )
        #expect(harness.provider.callCount == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.isEmpty)
    }

    @Test
    func hasImageProviderIsFalseWithoutVisionCapableProvider() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("unused")]
        )

        #expect(harness.runtime.hasImageProvider == false)
    }

    @Test
    func imageAttachmentDeferralReasonIsLocalAIPending() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("unused")]
        )

        #expect(harness.runtime.imageAttachmentDeferralReason == .pendingLocalAIPhase)
    }

    @Test
    func runtimeRejectsMalformedImageDataURLBeforePersisting() async throws {
        try await assertInvalidImageAttachmentRejected(
            "not-a-data-url",
            expectedHaltReason: .providerError("Image attachment data URL is malformed.")
        )
    }

    @Test
    func runtimeRejectsNonCanonicalBase64ImageDataURLsBeforePersisting() async throws {
        let dataURLs = [
            "data:image/png;base64,====",
            "data:image/png;base64,AAAA====",
            "data:image/png;base64,cG5n===",
            "data:image/png;base64,AB==",
            "data:image/png;base64,AAB=",
        ]

        for dataURL in dataURLs {
            try await assertInvalidImageAttachmentRejected(
                dataURL,
                expectedHaltReason: .providerError("Image attachment data URL is malformed.")
            )
        }
    }

    @Test
    func runtimeRejectsUnsupportedImageMIMEBeforePersisting() async throws {
        let gifBase64 = Data([0x47, 0x49, 0x46, 0x38]).base64EncodedString()
        let dataURL = "data:image/gif;base64,\(gifBase64)"

        try await assertInvalidImageAttachmentRejected(
            dataURL,
            expectedHaltReason: .providerError("Image attachment MIME type is not supported: image/gif.")
        )
    }

    @Test
    func runtimeRejectsOversizedImageDataURLBeforePersisting() async throws {
        let encoded = String(
            repeating: "A",
            count: ((AgentImageCapture.maxImageBytes + 2) / 3) * 4 + 4
        )
        let dataURL = "data:image/png;base64,\(encoded)"
        let expectedMessage =
            "Image attachment is too large (\(AgentImageCapture.maxImageBytes + 1) bytes; max \(AgentImageCapture.maxImageBytes) bytes)."

        try await assertInvalidImageAttachmentRejected(
            dataURL,
            expectedHaltReason: .providerError(expectedMessage)
        )
    }

    @Test
    func runtimeRejectsMultipleImageAttachmentsBeforePersisting() async throws {
        let attachments = [
            "data:image/png;base64,cG5n",
            "data:image/jpeg;base64,/9j/",
        ]

        try await assertInvalidImageAttachmentsRejected(
            attachments,
            expectedHaltReason: .providerError("Too many image attachments (2; max 1).")
        )
    }

    @Test
    func runtimeStopsAfterFiveToolIterationsAndAuditsCalls() async throws {
        let toolCall = #"{"type":"tool_call","name":"echo","input":{"text":"loop"}}"#
        let harness = try RuntimeHarness.make(
            tools: [EchoTool()],
            scripts: Array(repeating: .text(toolCall), count: 10)
        )
        let threadID = try harness.threadStore.create(title: "loop")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "loop", scope: "global")
        )

        #expect(response.finalAssistantContent == nil)
        #expect(response.haltReason == .maxIterationsReached)
        #expect(response.toolCallsExecuted == 5)
        #expect(harness.provider.callCount == 5)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .tool, .tool, .tool, .tool, .tool, .system])
        #expect(stored.filter { $0.role == .tool }.count == 5)
        #expect(stored.filter { $0.role == .tool }.allSatisfy { $0.toolCallJSON != nil })
        #expect(stored.last?.content == "Agent stopped after 5 tool iterations.")

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.count == 5)
        #expect(logs.allSatisfy { $0.toolName == "echo" })
    }

    @Test
    func toolDispatchErrorIsFedBackToModelInsteadOfAbortingTurn() async throws {
        let toolCall = #"{"type":"tool_call","name":"boom","input":{}}"#
        let finalText = "That tool failed, but here is what I can do instead."
        let harness = try RuntimeHarness.make(
            tools: [FailingTool()],
            scripts: [.text(toolCall), .text(finalText)]
        )
        let threadID = try harness.threadStore.create(title: "tool-error")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "go", scope: "global")
        )

        // The turn is NOT aborted on the tool failure: the model gets a second
        // turn (after the error is fed back) and produces a final answer.
        #expect(response.haltReason == .completed)
        #expect(response.finalAssistantContent == finalText)
        #expect(response.toolCallsExecuted == 1)
        #expect(harness.provider.callCount == 2)

        // The failure is persisted as a `.tool` transcript carrying the error
        // (no audit log, since the dispatch threw before one was written).
        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .tool, .agent])
        let toolMessage = try #require(stored.first { $0.role == .tool })
        let data = try #require(toolMessage.toolCallJSON)
        let transcript = try JSONDecoder().decode(AgentToolTranscript.self, from: data)
        #expect(transcript.error != nil)
        #expect(transcript.auditLogID == nil)

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }

    @Test
    func malformedToolCallEnvelopeReturnsProviderErrorWithoutDispatch() async throws {
        let harness = try RuntimeHarness.make(
            tools: [EchoTool()],
            scripts: [.text(#"{"type":"tool_call","input":{}}"#)]
        )
        let threadID = try harness.threadStore.create(title: "malformed")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "bad", scope: "global")
        )

        #expect(response.finalAssistantContent == nil)
        #expect(response.haltReason == .providerError("tool_call envelope missing non-empty name"))
        #expect(response.toolCallsExecuted == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user])
        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }

    @Test
    func malformedJSONEnvelopeReturnsProviderErrorWithoutAssistantMessage() async throws {
        let harness = try RuntimeHarness.make(
            tools: [EchoTool()],
            scripts: [.text(#"{"type":"tool_call","name":"echo","input":"#)]
        )
        let threadID = try harness.threadStore.create(title: "broken-json")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "broken", scope: "global")
        )

        #expect(response.finalAssistantContent == nil)
        #expect(response.haltReason == .providerError("malformed response envelope JSON"))
        #expect(response.toolCallsExecuted == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user])
        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }

    @Test
    func promptIncludesCurrentUserMessageOnce() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("done")]
        )
        let threadID = try harness.threadStore.create(title: "prompt")
        let userMessage = "unique-user-text"

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: userMessage, scope: "global")
        )

        let prompt = try #require(harness.provider.prompts.first)
        #expect(prompt.occurrences(of: userMessage) == 1)
        #expect(prompt.contains("user: \(userMessage)"))
        #expect(!prompt.contains("Current user message"))
    }

    @Test
    func contextPrefixIsEphemeralAndUserMessageStaysVisibleOnly() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("first done"), .text("second done")]
        )
        let threadID = try harness.threadStore.create(title: "file-context")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "summarize this",
                contextPrefix: "[System context from attached file \"x.txt\"]\nsecret-file-text\n[/System context]",
                scope: "global"
            )
        )

        let storedAfterFirstTurn = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(storedAfterFirstTurn.first?.role == .user)
        #expect(storedAfterFirstTurn.first?.content == "summarize this")
        #expect(storedAfterFirstTurn.allSatisfy { !$0.content.contains("secret-file-text") })

        let firstPrompt = try #require(harness.provider.prompts.first)
        #expect(firstPrompt.contains("Ephemeral context for this turn only:"))
        #expect(firstPrompt.contains("secret-file-text"))
        #expect(firstPrompt.contains("user: summarize this"))

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "next question", scope: "global")
        )

        let secondPrompt = try #require(harness.provider.prompts.last)
        #expect(!secondPrompt.contains("secret-file-text"))
    }

    @Test
    func providerErrorReturnsProviderErrorWithoutAssistantMessage() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.throwing(ScriptedProviderError.boom)]
        )
        let threadID = try harness.threadStore.create(title: "provider")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "fail", scope: "global")
        )

        #expect(response.finalAssistantContent == nil)
        #expect(response.haltReason == .providerError("boom"))
        #expect(response.toolCallsExecuted == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user])
    }

    @Test
    func finalJSONEnvelopeStoresContentOnly() async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text(#"{"type":"final","content":"Gotowe."}"#)]
        )
        let threadID = try harness.threadStore.create(title: "final-json")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "zrob", scope: "global")
        )

        #expect(response.finalAssistantContent == "Gotowe.")
        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.last?.content == "Gotowe.")
    }

    @Test
    func structuredToolCallsDispatchDirectlyAndBypassTextEnvelope() async throws {
        // Iteration 1: provider returns structured `toolCalls` (text is human prose,
        // NOT a JSON envelope — proves the structured path wins before
        // `AgentProviderTextEnvelope.parse` even runs).
        // Iteration 2: empty `toolCalls` + a `final` text envelope — proves the
        // legacy text path is still taken byte-for-byte when `toolCalls == []`.
        let harness = try RuntimeHarness.make(
            tools: [EchoTool()],
            scripts: [
                .structured(
                    text: "Sure, I'll echo that.",
                    toolCalls: [
                        AIToolCall(
                            name: "echo",
                            arguments: .object(["text": .string("structured")])
                        )
                    ]
                ),
                .text(#"{"type":"final","content":"Done."}"#),
            ]
        )
        let threadID = try harness.threadStore.create(title: "structured")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "echo structured", scope: "global")
        )

        #expect(response.finalAssistantContent == "Done.")
        #expect(response.haltReason == .completed)
        #expect(response.toolCallsExecuted == 1)
        #expect(harness.provider.callCount == 2)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .tool, .agent])
        #expect(stored.first(where: { $0.role == .tool })?.toolCallJSON != nil)
        #expect(stored.last?.content == "Done.")

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.toolName == "echo")
    }

    @Test
    func emptyToolCallsWithLegacyEnvelopeStillTakesTextPath() async throws {
        // `toolCalls == []` (Apple/Whisper behaviour) + a legacy
        // `{"type":"tool_call",...}` text body must still dispatch via the
        // unchanged `AgentProviderTextEnvelope.parse` path.
        let toolCall = #"{"type":"tool_call","name":"echo","input":{"text":"legacy"}}"#
        let harness = try RuntimeHarness.make(
            tools: [EchoTool()],
            scripts: [
                .text(toolCall),
                .text(#"{"type":"final","content":"Legacy done."}"#),
            ]
        )
        let threadID = try harness.threadStore.create(title: "legacy-path")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(threadID: threadID, userMessage: "legacy echo", scope: "global")
        )

        #expect(response.finalAssistantContent == "Legacy done.")
        #expect(response.haltReason == .completed)
        #expect(response.toolCallsExecuted == 1)

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.toolName == "echo")
    }

    private func assertInvalidImageAttachmentRejected(
        _ attachment: String,
        expectedHaltReason: AgentTurnHaltReason
    ) async throws {
        try await assertInvalidImageAttachmentsRejected(
            [attachment],
            expectedHaltReason: expectedHaltReason
        )
    }

    private func assertInvalidImageAttachmentsRejected(
        _ attachments: [String],
        expectedHaltReason: AgentTurnHaltReason
    ) async throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [
                .text("should not be called"),
                .text("should not be called either"),
            ],
            supportsImageAttachments: true
        )
        let threadID = try harness.threadStore.create(title: "invalid-image")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "co tu jest",
                attachments: attachments,
                scope: "global"
            )
        )

        #expect(response.finalAssistantContent == nil)
        #expect(response.haltReason == expectedHaltReason)
        #expect(response.toolCallsExecuted == 0)
        #expect(harness.provider.callCount == 0)

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.isEmpty)
    }
}

// File-private per the existing convention (each test file declares its own copy
// of this tiny stub to avoid same-target redeclaration collisions).
private struct EchoTool: AgentTool {
    let name = "echo"
    let description = "Echoes input."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        args
    }
}

private struct FailingTool: AgentTool {
    struct Boom: Error {}
    let name = "boom"
    let description = "Always fails."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        throw Boom()
    }
}
