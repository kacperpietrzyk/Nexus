import Foundation
import NexusAI
import NexusCore
import os

// Transcript, tool-dispatch, and prompt-building methods extracted from `AgentRuntime`
// to keep each file/type within the strict lint size budgets.

extension AgentRuntime {
    // MARK: - Tool dispatch

    func handleAIResponse(
        _ aiResponse: AIResponse,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        toolCallsExecuted: inout Int
    ) async throws -> AgentRuntimeStep {
        // Structured-first: providers with native tool-calling (e.g. MLX) populate
        // `aiResponse.toolCalls`. `AIToolCall.arguments` and `AgentToolCallEnvelope.input`
        // are now the same relocated `JSONValue` → 1:1 assignment, no JSON re-roundtrip.
        // When `aiResponse.toolCalls` is empty (Apple/Whisper), control falls through to
        // the legacy `AgentProviderTextEnvelope` path below, which is unchanged. The
        // multi-tool-call array case is NOT handled here — see the TODO at the dispatch.
        if let firstToolCall = aiResponse.toolCalls.first {
            if aiResponse.toolCalls.count > 1 {
                logger.warning(
                    """
                    Provider returned \(aiResponse.toolCalls.count, privacy: .public) tool calls; \
                    only the first (\(firstToolCall.name, privacy: .public)) is dispatched — \
                    the rest are silently discarded this turn.
                    """
                )
            }
            // TODO(Task 11/12): single-tool-call-per-turn is the intentional current
            // limitation. Supporting multiple structured tool calls requires either
            // configuring MLX to emit a single call per turn, or replacing this with a
            // per-call loop here that dispatches every entry in `aiResponse.toolCalls`.
            return try await handleToolCall(
                AgentToolCallEnvelope(name: firstToolCall.name, input: firstToolCall.arguments),
                request: request,
                window: window,
                aiResponse: aiResponse,
                toolCallsExecuted: &toolCallsExecuted
            )
        }

        switch AgentProviderTextEnvelope.parse(aiResponse.text) {
        case .toolCall(let toolCall):
            return try await handleToolCall(
                toolCall,
                request: request,
                window: window,
                aiResponse: aiResponse,
                toolCallsExecuted: &toolCallsExecuted
            )
        case .final(let content):
            // The weak on-device model routinely wraps a read intent in a
            // `nexus-proposal` block instead of emitting a tool call. If that block
            // names an allowlisted (read) tool, dispatch it here and loop — otherwise
            // the raw JSON would leak to the chat (or be stripped to an empty reply).
            // Writes are not in the allowlist, so they fall through to the confirm card.
            let readIntent = AgentProviderTextEnvelope.proposalReadIntent(
                content, allowlist: request.toolAllowlist)
            if let readIntent {
                return try await handleToolCall(
                    readIntent,
                    request: request,
                    window: window,
                    aiResponse: aiResponse,
                    toolCallsExecuted: &toolCallsExecuted
                )
            }
            try appendAssistantFinal(content, request: request, window: window, aiResponse: aiResponse)
            return .return(
                AgentTurnResponse(
                    finalAssistantContent: content,
                    haltReason: .completed,
                    toolCallsExecuted: toolCallsExecuted
                )
            )
        case .malformedToolCall(let reason):
            return .return(
                AgentTurnResponse(
                    finalAssistantContent: nil,
                    haltReason: .providerError(reason),
                    toolCallsExecuted: toolCallsExecuted
                )
            )
        }
    }

    func handleToolCall(
        _ toolCall: AgentToolCallEnvelope,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        aiResponse: AIResponse,
        toolCallsExecuted: inout Int
    ) async throws -> AgentRuntimeStep {
        let result: ToolDispatchResult
        do {
            result = try await dispatcher.dispatch(
                toolName: toolCall.name,
                input: toolCall.input,
                threadID: request.threadID
            )
        } catch is CancellationError {
            // A cancelled turn must propagate, not be fed back as a tool result.
            throw CancellationError()
        } catch {
            // Feed the tool failure back to the model as a tool result instead
            // of aborting the whole turn, so it can recover — retry with fixed
            // arguments, pick a different tool, or explain to the user. The
            // outer `while toolCallsExecuted < maxIterations` loop bounds this,
            // so a persistently failing tool still terminates.
            toolCallsExecuted += 1
            try appendToolErrorTranscript(
                call: toolCall,
                error: error,
                request: request,
                window: window,
                aiResponse: aiResponse
            )
            return .continueLoop
        }

        toolCallsExecuted += 1
        try appendToolTranscript(
            call: toolCall,
            result: result,
            request: request,
            window: window,
            aiResponse: aiResponse
        )
        return .continueLoop
    }

    // MARK: - Message appending

    func appendUserMessage(_ request: AgentTurnRequest, effectiveContent: String) throws {
        try messageStore.append(
            threadID: request.threadID,
            role: .user,
            content: effectiveContent,
            attachments: request.attachments
        )
    }

    func appendToolTranscript(
        call: AgentToolCallEnvelope,
        result: ToolDispatchResult,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        aiResponse: AIResponse
    ) throws {
        let transcript = AgentToolTranscript(
            call: call,
            result: result.output,
            auditLogID: result.auditLogID
        )
        try appendToolMessage(
            transcript, request: request, window: window, aiResponse: aiResponse)
    }

    /// Records a failed tool dispatch as a `.tool` transcript carrying the error,
    /// so the next loop iteration feeds it back to the model rather than ending
    /// the turn.
    func appendToolErrorTranscript(
        call: AgentToolCallEnvelope,
        error: Error,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        aiResponse: AIResponse
    ) throws {
        let transcript = AgentToolTranscript(
            call: call,
            result: .null,
            auditLogID: nil,
            error: String(describing: error)
        )
        try appendToolMessage(
            transcript, request: request, window: window, aiResponse: aiResponse)
    }

    private func appendToolMessage(
        _ transcript: AgentToolTranscript,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        aiResponse: AIResponse
    ) throws {
        let transcriptJSON = try encoder.encode(transcript)
        try messageStore.append(
            threadID: request.threadID,
            role: .tool,
            content: String(data: transcriptJSON, encoding: .utf8) ?? "{}",
            toolCallJSON: transcriptJSON,
            tokensIn: window.estimatedTokens,
            tokensOut: aiResponse.tokensUsed.completion,
            providerID: aiResponse.providerUsed.rawValue
        )
    }

    func appendAssistantFinal(
        _ content: String,
        request: AgentTurnRequest,
        window: AgentContextWindow,
        aiResponse: AIResponse
    ) throws {
        try messageStore.append(
            threadID: request.threadID,
            role: .agent,
            content: content,
            tokensIn: window.estimatedTokens,
            tokensOut: aiResponse.tokensUsed.completion,
            providerID: aiResponse.providerUsed.rawValue
        )
    }

    func appendMaxIterationsMessage(threadID: UUID) throws {
        try messageStore.append(
            threadID: threadID,
            role: .system,
            content: "Agent stopped after \(maxIterations) tool iterations.",
            providerID: "nexus-agent"
        )
    }

    // MARK: - Prompt building

    func makePrompt(request: AgentTurnRequest, window: AgentContextWindow) -> String {
        var sections = [
            "System:\n\(window.systemPrompt)",
            "Memory:\n\(window.memorySection.isEmpty ? "(none)" : window.memorySection)",
            "Recent messages:\n\(recentMessagesText(window.recentMessages))",
            "Tool definitions JSON:\n\(String(data: window.toolDefinitionsJSON, encoding: .utf8) ?? "[]")",
        ]

        if let contextPrefix = Self.normalizedContextPrefix(request.contextPrefix) {
            sections.insert("Ephemeral context for this turn only:\n\(contextPrefix)", at: 3)
        }

        if !window.retrievedHits.isEmpty {
            sections.append("Retrieved context:\n\(retrievedHitsText(window.retrievedHits))")
        }
        return sections.joined(separator: "\n\n")
    }

    /// System prompt for structured (native tool-calling) providers such as MLX.
    ///
    /// Those providers drive their turns from `AIRequest.messages` and take a
    /// single `.system` message — they do NOT consume the flat `makePrompt`
    /// output. So the non-transcript context that `makePrompt` folds into the flat
    /// prompt (memory, ephemeral turn context, RAG hits) must ALSO ride here, or
    /// it would be lost on the structured path. The recent-messages transcript and
    /// the tool-definitions JSON are deliberately omitted: the conversation is
    /// carried structurally via `messages`, and tools via `AIRequest.tools`.
    func makeStructuredSystemPrompt(request: AgentTurnRequest, window: AgentContextWindow) -> String {
        var sections = [
            window.systemPrompt,
            "Memory:\n\(window.memorySection.isEmpty ? "(none)" : window.memorySection)",
        ]
        if let contextPrefix = Self.normalizedContextPrefix(request.contextPrefix) {
            sections.append("Ephemeral context for this turn only:\n\(contextPrefix)")
        }
        if !window.retrievedHits.isEmpty {
            sections.append("Retrieved context:\n\(retrievedHitsText(window.retrievedHits))")
        }
        return sections.joined(separator: "\n\n")
    }

    nonisolated static func normalizedContextPrefix(_ contextPrefix: String?) -> String? {
        guard let trimmed = contextPrefix?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    func recentMessagesText(_ messages: [AgentMessageSnapshot]) -> String {
        guard !messages.isEmpty else { return "(none)" }
        return
            messages
            .map { message in
                let marker = message.attachments.isEmpty ? "" : " [attachments: \(message.attachments.count)]"
                return "\(message.role.rawValue): \(message.content)\(marker)"
            }
            .joined(separator: "\n")
    }

    func retrievedHitsText(_ hits: [RagHit]) -> String {
        hits
            .map { "- [\($0.kind)] \($0.title): \($0.snippet)" }
            .joined(separator: "\n")
    }
}
