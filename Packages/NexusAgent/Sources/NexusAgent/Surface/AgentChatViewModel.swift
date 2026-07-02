import Combine
import Foundation
import NexusAI

@MainActor
public final class AgentChatViewModel: ObservableObject {
    @Published public private(set) var threads: [AgentThread] = []
    @Published public private(set) var messages: [AgentMessage] = []
    @Published public private(set) var currentThreadID: UUID?
    @Published public private(set) var isThinking = false
    /// `true` while the on-device model is loading into memory for this turn —
    /// distinct from `isThinking` (generating) so the UI can show "Loading
    /// model…" instead of a silent freeze on the first slow cold load. Only ever
    /// set when a `warmChatModel` closure was injected (Mac local-model path).
    @Published public private(set) var isLoadingModel = false
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
    /// Wall-clock ceiling for a single turn (model load + generation). On expiry
    /// the composer is re-enabled and `recoverEngine` is invoked. Generous by
    /// default: a false timeout leaks a fully-loaded on-device model, so this
    /// must comfortably clear a legitimate slow first load.
    private let turnTimeout: Duration
    /// Abandon-and-recreate hook for a wedged engine. Called on a turn timeout so
    /// the NEXT send runs on a clean engine (a hung `MLX.eval` is non-cancellable
    /// and holds the engine busy gate — resetting in place would jam behind it).
    /// `nil` for callers without an on-device engine (tests / cloud-only).
    private let recoverEngine: (@MainActor () async -> Void)?
    /// Tracks whether the assigned model has been warmed this session so a turn
    /// only shows "Loading model…" + blocks on the load once. Reset to `false`
    /// after a timeout recovery, because the recreated engine is cold again.
    private var didWarmChatModel = false
    public let chatConfig: AssistantChatConfig
    private let proposalCoordinator: ProposalCoordinator?
    private let readinessProbe: (@MainActor () -> AssistantReadiness)?
    /// Pre-assembles a stuffed context for a turn (iOS extraction-only path). Wraps
    /// `ContextAssembler.assemble(...).renderedBlocks().joined(...)`; injected as a
    /// closure to keep the VM testable and avoid importing the assembler at every
    /// call site. `nil` on Mac / legacy callers — context then flows only through
    /// `ContextBuilder` inside the runtime, exactly as before.
    private let assembleContext: (@MainActor (ContextRecipe, ContextFocus, Date) async -> String)?

    /// Primary init — callers that don't use chat config (brief / schedule / legacy)
    /// omit `chatConfig`, `proposalCoordinator`, and `readinessProbe`; defaults keep
    /// existing behaviour.
    public init(
        runtime: AgentRuntime,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        memoryStore: AgentMemoryStore,
        voiceCapture: AgentVoiceCapture? = nil,
        chatModelAvailability: (@MainActor () -> Bool)? = nil,
        warmChatModel: (@MainActor () async -> Void)? = nil,
        chatConfig: AssistantChatConfig = .mac,
        proposalCoordinator: ProposalCoordinator? = nil,
        readinessProbe: (@MainActor () -> AssistantReadiness)? = nil,
        assembleContext: (@MainActor (ContextRecipe, ContextFocus, Date) async -> String)? = nil,
        turnTimeout: Duration = .seconds(90),
        recoverEngine: (@MainActor () async -> Void)? = nil
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
        self.readinessProbe = readinessProbe
        self.assembleContext = assembleContext
        self.turnTimeout = turnTimeout
        self.recoverEngine = recoverEngine
        self.isChatModelAvailable = chatModelAvailability?() ?? true

        reloadThreads()
    }

    /// Returns the current on-device assistant readiness. Defaults to `.ready`
    /// when no probe was injected (e.g. in tests or callers that don't gate on
    /// a local model). Called by the status badge in `AgentTopControl`.
    public func assistantReadiness() -> AssistantReadiness {
        readinessProbe?() ?? .ready
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
        Task {
            await warmChatModel()
            // Once appear-warm has loaded the model, a subsequent send skips the
            // blocking "Loading model…" step (the load already happened).
            self.didWarmChatModel = true
        }
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

    // rename/togglePin/delete/exportMarkdown/archiveAll/deleteAll: see extension below.

    @discardableResult
    public func send(
        userMessage: String,
        attachments: [String] = [],
        contextPrefix: String? = nil
    ) async -> AgentInputSendResult {
        guard let threadID = currentThreadID else { return .rejected(nil) }

        lastError = nil
        isThinking = true

        let initialMessageIDs = currentMessageIDs(threadID: threadID)
        let effectivePrefix = await assembledContextPrefix(
            userMessage: userMessage, callerPrefix: contextPrefix)

        let outcome = await runTurnWithTimeout(
            threadID: threadID,
            userMessage: userMessage,
            attachments: attachments,
            contextPrefix: effectivePrefix
        )

        // Re-enable the composer up front — even the timeout path must free it
        // before the (possibly slow) engine recovery below.
        isThinking = false
        isLoadingModel = false

        switch outcome {
        // Stale-completion guard (§5 BINDING contract — await-completion class):
        // If the user switched, created, or archived a thread while this turn was
        // suspended, `currentThreadID` has moved on. Writing this turn's
        // `lastError`/messages would clobber the fresher selection's state. The
        // captured local `threadID` is the guard token; no generation counter is
        // needed because @MainActor reloads here are synchronous.
        case .completed(.success(let response)):
            if currentThreadID == threadID {
                lastError = errorMessage(for: response.haltReason)
                // Strip proposal block from the assistant message before display/history.
                if let rawContent = response.finalAssistantContent {
                    stripAndCaptureProposal(rawContent: rawContent, threadID: threadID)
                }
                reloadMessages()
            }
        case .completed(.failure(let error)):
            if currentThreadID == threadID {
                lastError = error.localizedDescription
                reloadMessages()
            }
        case .timedOut:
            // Abandon the wedged engine and swap in a fresh one so the NEXT send
            // runs clean. Reset `didWarmChatModel` because the recreated engine
            // is cold — the next turn must re-warm (and re-show "Loading model…")
            // instead of cold-loading silently inside `runTurn`.
            await recoverEngine?()
            didWarmChatModel = false
            if currentThreadID == threadID {
                lastError = Self.turnTimeoutMessage
                reloadMessages()
            }
        }

        let accepted = !currentMessageIDs(threadID: threadID).subtracting(initialMessageIDs).isEmpty
        return accepted ? .accepted : .rejected(lastError)
    }

    /// Friendly message shown when a turn exceeds `turnTimeout`.
    static let turnTimeoutMessage =
        "The assistant took too long to respond and was reset. Please try again."

    private enum TurnOutcome {
        case completed(Result<AgentTurnResponse, Error>)
        case timedOut
    }

    /// Guards a `CheckedContinuation` so exactly one of the racing tasks (work vs
    /// timer) resumes it; the loser's call is a no-op. `@MainActor`-isolated, so
    /// the two resume calls are serialized without a lock.
    @MainActor
    private final class SingleResume {
        private var continuation: CheckedContinuation<TurnOutcome, Never>?

        init(_ continuation: CheckedContinuation<TurnOutcome, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: TurnOutcome) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: value)
        }
    }

    /// Runs the turn (model load + generation) against a wall-clock timeout.
    ///
    /// Deliberately NOT a `withThrowingTaskGroup`: a group awaits ALL child tasks
    /// at scope exit, so a hung (non-cancellable) `MLX.eval` would keep the group
    /// — and thus `send` — suspended forever, defeating the timeout. Instead the
    /// work and the timer race to resume a single continuation; on timeout the
    /// work task is simply ABANDONED (left running, holding the wedged engine) and
    /// the caller recreates the engine.
    private func runTurnWithTimeout(
        threadID: UUID,
        userMessage: String,
        attachments: [String],
        contextPrefix: String?
    ) async -> TurnOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<TurnOutcome, Never>) in
            let gate = SingleResume(continuation)
            let work = Task { @MainActor in
                if let warmChatModel = self.warmChatModel, !self.didWarmChatModel {
                    self.isLoadingModel = true
                    await warmChatModel()
                    self.didWarmChatModel = true
                    self.isLoadingModel = false
                }
                do {
                    let response = try await self.runtime.runTurn(
                        AgentTurnRequest(
                            threadID: threadID,
                            userMessage: userMessage,
                            attachments: attachments,
                            contextPrefix: contextPrefix,
                            scope: "global",
                            toolAllowlist: self.chatConfig.toolNames,
                            systemPromptOverride: self.chatConfig.systemPrompt
                        )
                    )
                    gate.resume(returning: .completed(.success(response)))
                } catch {
                    gate.resume(returning: .completed(.failure(error)))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: self.turnTimeout)
                gate.resume(returning: .timedOut)
                // Best-effort: a hung MLX.eval ignores cancellation. The work task
                // is abandoned regardless; the engine is recreated by the caller.
                work.cancel()
            }
        }
    }

    /// For extraction-only configs (iOS, `allowsToolCalling == false`), pre-assembles a
    /// stuffed context via the injected `assembleContext` closure and merges it with any
    /// caller-supplied `contextPrefix` (e.g. file attachments from the input bar) — neither
    /// is dropped. Returns `callerPrefix` unchanged when no closure was injected or the
    /// config allows tool-calling (Mac path), so Mac behaviour is byte-identical to before.
    private func assembledContextPrefix(userMessage: String, callerPrefix: String?) async -> String? {
        guard !chatConfig.allowsToolCalling, let assembleContext else { return callerPrefix }
        let base = chatConfig.contextRecipe
        // The iOS recipe ships an empty RAG query string; bind it to this turn's message
        // so retrieval runs against what the user actually asked (not "").
        let perTurnRecipe = ContextRecipe(
            includeEntity: base.includeEntity,
            linkGraphDepth: base.linkGraphDepth,
            repoSlices: base.repoSlices,
            ragQuery: base.ragQuery.map { RagQuerySpec(query: userMessage, limit: $0.limit) },
            tokenBudget: base.tokenBudget)
        let assembled = await assembleContext(perTurnRecipe, ContextFocus(freeText: userMessage), Date())
        let parts = [assembled, callerPrefix].compactMap { part -> String? in
            guard let part, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return part
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Accept the pending proposal for the given message id.
    /// Routes through `ProposalCoordinator` → `ToolDispatcher` (audited).
    /// Clears the pending proposal entry only on success; on failure the
    /// entry is kept so the confirm card stays visible and `lastError` is set.
    public func acceptProposal(messageID: UUID) async throws {
        guard let proposal = pendingProposals[messageID],
            let coordinator = proposalCoordinator
        else { return }
        do {
            try await coordinator.accept(proposal, threadID: currentThreadID)
            pendingProposals[messageID] = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
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

// MARK: - Thread management ops (extracted to keep AgentChatViewModel under type_body_length limit)

extension AgentChatViewModel {
    /// Renames the thread to `title`. A blank title collapses to "Untitled" (in the store).
    public func rename(threadID: UUID, title: String) {
        do {
            try threadStore.rename(id: threadID, title: title)
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        reloadThreads()
    }

    /// Toggles the pin state of `threadID`. Pinned threads sort above unpinned ones.
    public func togglePin(threadID: UUID) {
        do {
            try threadStore.togglePin(id: threadID)
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        reloadThreads()
    }

    /// Hard-deletes the thread (and navigates away if it is currently selected).
    public func delete(threadID: UUID) {
        do {
            try threadStore.delete(id: threadID)
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

    /// Returns a Markdown string for the thread. Empty string on error.
    public func exportMarkdown(threadID: UUID) -> String {
        (try? threadStore.exportMarkdown(id: threadID, messageStore: messageStore)) ?? ""
    }

    /// Archives all threads with IDs in `ids`. Silently skips unknown IDs.
    public func archiveAll(threadIDs: [UUID]) {
        for id in threadIDs {
            try? threadStore.archive(id: id)
            if currentThreadID == id {
                currentThreadID = nil
                messages = []
            }
        }
        lastError = nil
        reloadThreads()
    }

    /// Hard-deletes all threads with IDs in `ids`.
    public func deleteAll(threadIDs: [UUID]) {
        for id in threadIDs {
            try? threadStore.delete(id: id)
            if currentThreadID == id {
                currentThreadID = nil
                messages = []
            }
        }
        lastError = nil
        reloadThreads()
    }

    /// Restores an archived thread (clears `archivedAt`).
    public func unarchive(threadID: UUID) {
        do {
            try threadStore.unarchive(id: threadID)
        } catch {
            lastError = error.localizedDescription
            return
        }
        lastError = nil
        reloadThreads()
    }

    /// Restores all threads with IDs in `ids` from archive. Silently skips unknown IDs.
    public func unarchiveAll(threadIDs: [UUID]) {
        for id in threadIDs {
            try? threadStore.unarchive(id: id)
        }
        lastError = nil
        reloadThreads()
    }
}
