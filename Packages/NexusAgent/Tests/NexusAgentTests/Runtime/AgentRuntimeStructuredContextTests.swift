import Foundation
import NexusAI
import Testing

@testable import NexusAgent

/// Guards the structured-provider (MLX) context path. The flat `AIRequest.prompt`
/// is consumed only by Apple/Whisper; MLX drives its turns from
/// `AIRequest.messages` and MUST receive memory/RAG/ephemeral context via
/// `AIRequest.systemPrompt` instead — otherwise dropping the flat prompt as the
/// MLX user turn would silently regress context.
@Suite("AgentRuntime structured context")
struct AgentRuntimeStructuredContextTests {
    @MainActor
    @Test("ephemeral context + persona land in systemPrompt for the structured path")
    func structuredSystemPromptCarriesContext() async throws {
        let harness = try RuntimeHarness.make(tools: [], scripts: [.text("done")])
        let threadID = try harness.threadStore.create(title: "structured-context")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "Jakie mam jutro spotkania?",
                contextPrefix: "EPHEMERAL-CONTEXT-MARKER",
                scope: "assistant",
                systemPromptOverride: "You are Nexus Assistant."
            )
        )

        // The structured system prompt keeps the persona AND folds in the ephemeral
        // context that previously lived only in the flat prompt.
        let system = try #require(harness.provider.lastSystemPrompt)
        #expect(system.contains("You are Nexus Assistant."))
        #expect(system.contains("EPHEMERAL-CONTEXT-MARKER"))
    }

    @MainActor
    @Test("structured messages end with the current user turn (no flat-transcript reliance)")
    func structuredMessagesEndWithCurrentUserTurn() async throws {
        let harness = try RuntimeHarness.make(tools: [], scripts: [.text("done")])
        let threadID = try harness.threadStore.create(title: "structured-turns")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "Jakie mam jutro spotkania?",
                scope: "assistant",
                systemPromptOverride: "You are Nexus Assistant."
            )
        )

        let messages = try #require(harness.provider.lastMessages)
        #expect(messages.last?.role == .user)
        #expect(messages.last?.text == "Jakie mam jutro spotkania?")
    }
}
