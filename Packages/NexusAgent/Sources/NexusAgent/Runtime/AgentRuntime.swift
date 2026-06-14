import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import os

public enum AgentTurnHaltReason: Sendable, Equatable {
    case completed
    case maxIterationsReached
    case providerError(String)
}

public struct AgentTurnResponse: Sendable, Equatable {
    public let finalAssistantContent: String?
    public let haltReason: AgentTurnHaltReason
    public let toolCallsExecuted: Int

    public init(
        finalAssistantContent: String?,
        haltReason: AgentTurnHaltReason,
        toolCallsExecuted: Int
    ) {
        self.finalAssistantContent = finalAssistantContent
        self.haltReason = haltReason
        self.toolCallsExecuted = toolCallsExecuted
    }
}

// Kept for AgentInputBar compatibility (Task 21 removes when it rewires the banner).
public enum ImageAttachmentDeferralReason: Sendable, Equatable {
    case pendingLocalAIPhase
}

@MainActor
public final class AgentRuntime {
    let router: AIRouter
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    nonisolated(unsafe) let contextBuilder: ContextBuilder
    let dispatcher: ToolDispatcher
    let maxIterations: Int
    let encoder: JSONEncoder
    public let hasImageProvider: Bool
    let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "AgentRuntime")

    #if canImport(Vision)
    private let ocrPipeline: OCRPipeline?
    #endif

    // Base init used by all call sites that do not need OCR (default path, no Vision dep).
    public convenience init(
        router: AIRouter,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        contextBuilder: ContextBuilder,
        dispatcher: ToolDispatcher,
        maxIterations: Int = 5
    ) {
        #if canImport(Vision)
        self.init(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: dispatcher,
            maxIterations: maxIterations,
            ocrPipeline: nil
        )
        #else
        self.init(
            router: router,
            threadStore: threadStore,
            messageStore: messageStore,
            contextBuilder: contextBuilder,
            dispatcher: dispatcher,
            maxIterations: maxIterations,
            _ocrPipelineUnavailable: ()
        )
        #endif
    }

    #if canImport(Vision)
    /// Designated init for Vision-capable platforms; accepts an optional `OCRPipeline`
    /// so image attachments are OCR-extracted and injected into the request rather than
    /// being rejected. Pass `nil` (default) to keep the pre-OCR rejection behaviour.
    public init(
        router: AIRouter,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        contextBuilder: ContextBuilder,
        dispatcher: ToolDispatcher,
        maxIterations: Int = 5,
        ocrPipeline: OCRPipeline? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        self.router = router
        self.threadStore = threadStore
        self.messageStore = messageStore
        self.contextBuilder = contextBuilder
        self.dispatcher = dispatcher
        self.maxIterations = maxIterations
        self.encoder = encoder
        self.ocrPipeline = ocrPipeline
        self.hasImageProvider = ocrPipeline != nil
    }
    #else
    // Non-Vision platforms (e.g. watchOS if ever added to targets): no OCRPipeline available.
    // The `_ocrPipelineUnavailable` label exists only to disambiguate from the convenience init above.
    fileprivate init(
        router: AIRouter,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        contextBuilder: ContextBuilder,
        dispatcher: ToolDispatcher,
        maxIterations: Int = 5,
        _ocrPipelineUnavailable: Void
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        self.router = router
        self.threadStore = threadStore
        self.messageStore = messageStore
        self.contextBuilder = contextBuilder
        self.dispatcher = dispatcher
        self.maxIterations = maxIterations
        self.encoder = encoder
        self.hasImageProvider = false
    }
    #endif

    public func runTurn(_ request: AgentTurnRequest) async throws -> AgentTurnResponse {
        // Validate, OCR-extract, and gate image attachments before persisting.
        let prepared: PreparedRequest
        switch await prepareAttachments(for: request) {
        case .reject(let response):
            return response
        case .proceed(let p):
            prepared = p
        }

        try appendUserMessage(request, effectiveContent: prepared.effectiveUserMessage)
        try threadStore.touch(id: request.threadID)

        var toolCallsExecuted = 0

        while toolCallsExecuted < maxIterations {
            let window = try await buildContext(for: request)
            let aiResponse: AIResponse
            do {
                aiResponse = try await routeAI(
                    request: request,
                    effectiveAttachments: prepared.effectiveAttachments,
                    window: window,
                    toolCallsExecuted: toolCallsExecuted
                )
            } catch AgentRuntimeProviderError.response(let response) {
                return response
            }

            switch try await handleAIResponse(
                aiResponse,
                request: request,
                window: window,
                toolCallsExecuted: &toolCallsExecuted
            ) {
            case .continueLoop:
                continue
            case .return(let response):
                return response
            }
        }

        try appendMaxIterationsMessage(threadID: request.threadID)
        return AgentTurnResponse(
            finalAssistantContent: nil,
            haltReason: .maxIterationsReached,
            toolCallsExecuted: toolCallsExecuted
        )
    }

    // MARK: - Attachment preprocessing

    private struct PreparedRequest {
        let effectiveUserMessage: String
        let effectiveAttachments: [String]
    }

    private enum PrepareResult {
        case proceed(PreparedRequest)
        case reject(AgentTurnResponse)
    }

    /// Validates, and when an OCRPipeline is present, extracts text from, any image
    /// attachments. Returns `.reject` with a friendly message on validation failure or
    /// when no image provider is available; `.proceed` with the effective user message
    /// and (possibly empty) attachments otherwise.
    private func prepareAttachments(for request: AgentTurnRequest) async -> PrepareResult {
        guard !request.attachments.isEmpty else {
            return .proceed(
                PreparedRequest(
                    effectiveUserMessage: request.userMessage,
                    effectiveAttachments: []
                )
            )
        }

        do {
            try AgentImageCapture.validateAttachmentDataURLs(request.attachments)
        } catch {
            return .reject(
                AgentTurnResponse(
                    finalAssistantContent: nil,
                    haltReason: .providerError(Self.imageValidationMessage(for: error)),
                    toolCallsExecuted: 0
                )
            )
        }

        guard hasImageProvider else {
            return .reject(
                AgentTurnResponse(
                    finalAssistantContent: nil,
                    haltReason: .providerError(Self.imageProviderUnavailableMessage),
                    toolCallsExecuted: 0
                )
            )
        }

        #if canImport(Vision)
        if let pipeline = ocrPipeline {
            let ocrBlocks = await extractOCRBlocks(from: request.attachments, using: pipeline)
            let injectedMessage =
                ocrBlocks.isEmpty
                ? request.userMessage
                : ocrBlocks.joined(separator: "\n") + "\n" + request.userMessage
            // Attachments consumed by OCR — omit from AIRequest so routing does not
            // attempt a vision-provider path (no provider currently supports images).
            return .proceed(
                PreparedRequest(effectiveUserMessage: injectedMessage, effectiveAttachments: [])
            )
        }
        #endif

        return .proceed(
            PreparedRequest(
                effectiveUserMessage: request.userMessage,
                effectiveAttachments: request.attachments
            )
        )
    }

    private func buildContext(for request: AgentTurnRequest) async throws -> AgentContextWindow {
        try await contextBuilder.build(
            threadID: request.threadID,
            scope: request.scope,
            userPrompt: request.userMessage,
            toolAllowlist: request.toolAllowlist
        )
    }

    private func routeAI(
        request: AgentTurnRequest,
        effectiveAttachments: [String],
        window: AgentContextWindow,
        toolCallsExecuted: Int
    ) async throws -> AIResponse {
        do {
            return try await router.route(
                makeAIRequest(
                    request: request,
                    effectiveAttachments: effectiveAttachments,
                    window: window
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Prefer a `LocalizedError` message (AIRouterError now conforms, so
            // routing failures read as real sentences) but fall back to
            // `String(describing:)` for plain errors — `localizedDescription`
            // would otherwise turn those into the generic "operation couldn't be
            // completed" string.
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            throw AgentRuntimeProviderError.response(
                AgentTurnResponse(
                    finalAssistantContent: nil,
                    haltReason: .providerError(message),
                    toolCallsExecuted: toolCallsExecuted
                )
            )
        }
    }

    private func makeAIRequest(
        request: AgentTurnRequest,
        effectiveAttachments: [String],
        window: AgentContextWindow
    ) -> AIRequest {
        AIRequest(
            prompt: makePrompt(request: request, window: window),
            capability: effectiveAttachments.isEmpty && window.shouldEscalate ? .longContext : .generate,
            connectivity: connectivity(for: request),
            cost: cost(for: request, effectiveAttachments: effectiveAttachments),
            providerPreference: providerPreference(for: request.providerHint),
            context: window.retrievedHits.map(\.itemID.uuidString),
            attachments: effectiveAttachments,
            messages: structuredMessages(from: window),
            tools: toolSpecs(from: dispatcher.toolManifest, allowlist: request.toolAllowlist),
            systemPrompt: window.systemPrompt
        )
    }

    /// Maps the context window's recent transcript to structured `AIChatMessage`
    /// values for native tool-calling providers (e.g. MLX). Non-structured providers
    /// (Apple/Whisper) ignore `messages` and use the flattened `prompt`.
    ///
    /// NOTE: `messages` (this) and `systemPrompt` (= `window.systemPrompt`) are NOT
    /// context-complete. `makePrompt` additionally folds `window.memorySection`,
    /// `window.retrievedHits` (RAG), and ephemeral `request.contextPrefix` into the
    /// flat `prompt` — none of that is reflected here. A provider that consumes
    /// `messages` instead of `prompt` would lose memory + RAG hits + ephemeral file
    /// context. The MLX integration (Task 11/12) must therefore either keep consuming
    /// `prompt`, or be wired to carry that extra context into the structured form too.
    private func structuredMessages(from window: AgentContextWindow) -> [AIChatMessage] {
        window.recentMessages.map { snapshot in
            AIChatMessage(role: Self.chatRole(for: snapshot.role), text: snapshot.content)
        }
    }

    nonisolated private static func chatRole(for role: AgentMessageRole) -> AIChatMessage.Role {
        switch role {
        case .user: .user
        case .agent: .assistant
        case .tool: .tool
        case .system: .system
        }
    }

    /// Converts the dispatcher's tool manifest into `[AIToolSpec]` so native
    /// tool-calling providers can advertise callable tools to the model.
    /// When `allowlist` is non-nil, only entries whose `name` is in the list
    /// are included; `nil` passes the full manifest unchanged.
    private func toolSpecs(from manifest: ToolManifestDTO, allowlist: [String]? = nil) -> [AIToolSpec] {
        let entries = allowlist.map { a in manifest.tools.filter { a.contains($0.name) } } ?? manifest.tools
        return entries.map { entry in
            let encodedSchema =
                (try? encoder.encode(entry.inputSchema)).flatMap {
                    String(data: $0, encoding: .utf8)
                }
            if encodedSchema == nil {
                // Should never happen (`JSONSchema` is Codable). Fall back to an
                // accepts-anything `{}` so the model still sees the tool, but surface
                // it — a silent `{}` would let the model pass arbitrary args.
                logger.error(
                    """
                    Failed to encode inputSchema for tool \(entry.name, privacy: .public); \
                    advertising empty `{}` schema (accepts anything) as fallback.
                    """
                )
            }
            return AIToolSpec(
                name: entry.name,
                description: entry.description,
                parametersJSONSchema: encodedSchema ?? "{}"
            )
        }
    }

    public var imageAttachmentDeferralReason: ImageAttachmentDeferralReason? {
        hasImageProvider ? nil : .pendingLocalAIPhase
    }

    nonisolated private static let imageProviderUnavailableMessage =
        "Image attachments arrive with on-device AI in the next phase."

    nonisolated private static func imageValidationMessage(for error: Error) -> String {
        guard let captureError = error as? AgentImageCaptureError else {
            return "Image attachment is invalid."
        }

        switch captureError {
        case .emptyImage, .malformedImageDataURL:
            return "Image attachment data URL is malformed."
        case .unsupportedImageMIME(let mime):
            return "Image attachment MIME type is not supported: \(mime)."
        case .tooManyImages(let maxCount, let actualCount):
            return "Too many image attachments (\(actualCount); max \(maxCount))."
        case .imageTooLarge(let maxBytes, let actualBytes):
            return "Image attachment is too large (\(actualBytes) bytes; max \(maxBytes) bytes)."
        case .imageTotalTooLarge(let maxBytes, let actualBytes):
            return "Image attachments are too large in total (\(actualBytes) bytes; max \(maxBytes) bytes)."
        case .noCloudProviderConsented:
            return Self.imageProviderUnavailableMessage
        }
    }

    // Methods extracted to AgentRuntimeTranscript.swift:
    // handleAIResponse, handleToolCall, appendUserMessage, appendToolTranscript,
    // appendAssistantFinal, appendMaxIterationsMessage,
    // makePrompt, normalizedContextPrefix, recentMessagesText, retrievedHitsText.

    private func providerPreference(for providerHint: String?) -> ProviderPreference {
        switch providerHint?.lowercased() {
        case "claude", "claude" + "shell":
            .auto
        default:
            .auto
        }
    }

    private func connectivity(for _: AgentTurnRequest) -> ConnectivityPreference {
        .offlineOnly
    }

    private func cost(for _: AgentTurnRequest, effectiveAttachments: [String]) -> CostPreference {
        // After OCR the effective attachments list is empty; keep cost as .free
        // since we are no longer routing to a paid vision provider.
        if !effectiveAttachments.isEmpty {
            return .anyPaid
        }

        return .free
    }

}
// OCR helpers live in AgentRuntimeOCR.swift (#if canImport(Vision)).

enum AgentProviderTextEnvelope: Equatable {
    case toolCall(AgentToolCallEnvelope)
    case final(String)
    case malformedToolCall(String)

    static func parse(_ text: String) -> AgentProviderTextEnvelope {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
            return .final(text)
        }

        guard let raw = try? JSONDecoder().decode(RawEnvelope.self, from: data) else {
            return .malformedToolCall("malformed response envelope JSON")
        }

        switch raw.type {
        case "tool_call":
            guard let name = raw.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else {
                return .malformedToolCall("tool_call envelope missing non-empty name")
            }
            return .toolCall(AgentToolCallEnvelope(name: name, input: raw.input ?? .object([:])))
        case "final":
            return .final(raw.content ?? "")
        default:
            return .final(text)
        }
    }

    private struct RawEnvelope: Decodable {
        let type: String?
        let name: String?
        let input: JSONValue?
        let content: String?
    }
}

// Internal so AgentRuntimeTranscript.swift (same module, different file) can use these.
enum AgentRuntimeStep {
    case continueLoop
    case `return`(AgentTurnResponse)
}

enum AgentRuntimeProviderError: Error {
    case response(AgentTurnResponse)
}

struct AgentToolCallEnvelope: Codable, Equatable, Sendable {
    let name: String
    let input: JSONValue
}

struct AgentToolTranscript: Codable, Equatable, Sendable {
    let call: AgentToolCallEnvelope
    let result: JSONValue
    /// Nil when the dispatch failed before an audit-log entry was written
    /// (the `error` case below).
    let auditLogID: UUID?
    /// Set when the tool dispatch threw: the failure is recorded as a tool
    /// result and fed back to the model (instead of aborting the turn) so it
    /// can recover. Nil on the success path.
    let error: String?

    init(call: AgentToolCallEnvelope, result: JSONValue, auditLogID: UUID?, error: String? = nil) {
        self.call = call
        self.result = result
        self.auditLogID = auditLogID
        self.error = error
    }
}
