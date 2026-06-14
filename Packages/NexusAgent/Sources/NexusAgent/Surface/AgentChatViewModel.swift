import Combine
import Foundation

@MainActor
public final class AgentChatViewModel: ObservableObject {
    @Published public private(set) var threads: [AgentThread] = []
    @Published public private(set) var messages: [AgentMessage] = []
    @Published public private(set) var currentThreadID: UUID?
    @Published public private(set) var isThinking = false
    @Published public private(set) var lastError: String?
    /// Whether an on-device chat model is downloaded and assigned. `true` when no probe
    /// was injected (Mac / tests / callers that don't gate on a local model) so the
    /// "model not downloaded" banner stays hidden by default. Refreshed via
    /// `refreshChatModelAvailability()` on view appearance.
    @Published public private(set) var isChatModelAvailable = true
    /// In-memory map from agent message id → parsed `Proposal`. Populated after each
    /// turn whose assistant text contained a valid `nexus-proposal` block. The raw
    /// block is stripped from the persisted `AgentMessage.content` before this is set
    /// (leak-prevention landmine §4). Cleared on accept or reject.
    @Published public private(set) var pendingProposals: [UUID: Proposal] = [:]

    public let voiceCapture: AgentVoiceCapture?

    private let runtime: AgentRuntime
    private let threadStore: AgentThreadStore
    private let messageStore: AgentMessageStore
    private let memoryStore: AgentMemoryStore
    private let chatModelAvailabilityProbe: (@MainActor () -> Bool)?
    private let warmChatModel: (@MainActor () async -> Void)?
    private let chatConfig: AssistantChatConfig
    private let proposalCoordinator: ProposalCoordinator?

    /// Primary init — callers that don't use chat config (brief / schedule / legacy)
    /// omit `chatConfig` and `proposalCoordinator`; defaults keep existing behaviour.
    public init(
        runtime: AgentRuntime,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        memoryStore: AgentMemoryStore,
        voiceCapture: AgentVoiceCapture? = nil,
        chatModelAvailability: (@MainActor () -> Bool)? = nil,
        warmChatModel: (@MainActor () async -> Void)? = nil,
        chatConfig: AssistantChatConfig = .mac,
        proposalCoordinator: ProposalCoordinator? = nil
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.messageStore = messageStore
        self.memoryStore = memoryStore
        self.voiceCapture = voiceCapture
        self.chatModelAvailabilityProbe = chatModelAvailability
        self.warmChatModel = warmChatModel
        self.chatConfig = chatConfig
        self.proposalCoordinator = proposalCoordinator
        self.isChatModelAvailable = chatModelAvailability?() ?? true

        reloadThreads()
    }

    /// Warms the assigned on-device chat model if one is assigned but not yet
    /// loaded. Call from the chat view's `onAppear` so an assigned local model
    /// (e.g. Qwen) actually serves chat even when the "preload on launch" toggle
    /// is off — otherwise a cold MLX provider stays invisible to the router and
    /// every prompt dead-ends at Apple Intelligence (and its guardrail). No-op
    /// when no warm closure was injected (iOS / tests). Fire-and-forget; the
    /// injected closure owns the assigned-and-on-disk guard.
    public func warmChatModelIfNeeded() {
        guard let warmChatModel else { return }
        Task { await warmChatModel() }
    }

    /// Re-evaluates whether the on-device chat model is present. A no-op when no probe
    /// was injected. Call from the chat view's `onAppear` so the banner clears once the
    /// user returns from downloading the model in Settings.
    public func refreshChatModelAvailability() {
        guard let probe = chatModelAvailabilityProbe else { return }
        isChatModelAvailable = probe()
    }

    public func reloadThreads() {
        threads = (try? threadStore.allActive()) ?? []
    }

    public func selectThread(id: UUID) {
        lastError = nil
        currentThreadID = id
        reloadMessages()
    }

    public func createThread(title: String = "") {
        guard let id = try? threadStore.create(title: title) else { return }
        lastError = nil
        reloadThreads()
        selectThread(id: id)
    }

    public func archive(threadID: UUID) {
        do {
            try threadStore.archive(id: threadID)
        } catch {
            lastError = error.localizedDescription
            return
        }

        lastError = nil
        if currentThreadID == threadID {
            currentThreadID = nil
            messages = []
        }
        reloadThreads()
    }

    @discardableResult
    public func send(
        userMessage: String,
        attachments: [String] = [],
        contextPrefix: String? = nil
    ) async -> AgentInputSendResult {
        guard let threadID = currentThreadID else { return .rejected(nil) }

        lastError = nil
        isThinking = true
        defer { isThinking = false }

        let initialMessageIDs = currentMessageIDs(threadID: threadID)
        do {
            let response = try await runtime.runTurn(
                AgentTurnRequest(
                    threadID: threadID,
                    userMessage: userMessage,
                    attachments: attachments,
                    contextPrefix: contextPrefix,
                    scope: "global",
                    toolAllowlist: chatConfig.toolNames,
                    systemPromptOverride: chatConfig.systemPrompt
                )
            )
            // Stale-completion guard (§5 BINDING contract — await-completion class):
            // If the user switched, created, or archived a thread while this turn was
            // suspended at `runtime.runTurn`, `currentThreadID` has moved on. Writing
            // this turn's `lastError`/messages would clobber the fresher selection's
            // state. The captured local `threadID` is the guard token; no generation
            // counter is needed because @MainActor reloads here are synchronous.
            if currentThreadID == threadID {
                lastError = errorMessage(for: response.haltReason)
                // Strip proposal block from the assistant message before display/history.
                if let rawContent = response.finalAssistantContent {
                    stripAndCaptureProposal(
                        rawContent: rawContent,
                        threadID: threadID
                    )
                }
                reloadMessages()
            }
        } catch {
            if currentThreadID == threadID {
                lastError = error.localizedDescription
                reloadMessages()
            }
        }

        let accepted = !currentMessageIDs(threadID: threadID).subtracting(initialMessageIDs).isEmpty
        return accepted ? .accepted : .rejected(lastError)
    }

    /// Accept the pending proposal for the given message id.
    /// Routes through `ProposalCoordinator` → `ToolDispatcher` (audited).
    /// Clears the pending proposal entry regardless of success/failure.
    public func acceptProposal(messageID: UUID) async throws {
        guard let proposal = pendingProposals[messageID],
            let coordinator = proposalCoordinator
        else { return }
        pendingProposals[messageID] = nil
        try await coordinator.accept(proposal, threadID: currentThreadID)
    }

    /// Reject the pending proposal for the given message id — zero side effects.
    public func rejectProposal(messageID: UUID) {
        guard let proposal = pendingProposals[messageID] else { return }
        proposalCoordinator?.reject(proposal)
        pendingProposals[messageID] = nil
    }

    // MARK: - Proposal stripping (leak-prevention §4)

    /// Parses the raw assistant content for a `nexus-proposal` block.
    /// - Overwrites the persisted `AgentMessage.content` with the stripped `displayText`
    ///   so history is never polluted with raw JSON fences.
    /// - Captures any parsed `Proposal` in `pendingProposals` keyed by message id.
    private func stripAndCaptureProposal(rawContent: String, threadID: UUID) {
        let parsed = ChatProposalParser.parse(rawContent)
        // If nothing to strip and no proposal, skip the store round-trip.
        guard parsed.displayText != rawContent || parsed.proposal != nil else { return }

        // Find the agent message that carries the raw content and overwrite it.
        let window = (try? messageStore.slidingWindow(threadID: threadID, last: 200)) ?? []
        guard let agentMessage = window.last(where: { $0.role == .agent && $0.content == rawContent })
        else { return }

        let messageID = agentMessage.id
        // Persist stripped text — critical: no raw block in DB.
        try? messageStore.overwriteContent(id: messageID, content: parsed.displayText)

        if let proposal = parsed.proposal {
            pendingProposals[messageID] = proposal
        }
    }

    public func isImageCaptureAvailable() -> Bool {
        runtime.hasImageProvider
    }

    public func imageAttachmentDeferralReason() -> ImageAttachmentDeferralReason? {
        runtime.imageAttachmentDeferralReason
    }

    private func reloadMessages() {
        guard let id = currentThreadID else {
            messages = []
            return
        }

        messages = (try? messageStore.slidingWindow(threadID: id, last: 200)) ?? []
    }

    private func currentMessageIDs(threadID: UUID) -> Set<UUID> {
        Set(((try? messageStore.slidingWindow(threadID: threadID, last: 200)) ?? []).map(\.id))
    }

    private func errorMessage(for haltReason: AgentTurnHaltReason) -> String? {
        switch haltReason {
        case .completed:
            nil
        case .maxIterationsReached:
            "Agent stopped after reaching the maximum number of tool iterations."
        case .providerError(let message):
            message
        }
    }
}
