import Combine
import Foundation

@MainActor
public final class AgentChatViewModel: ObservableObject {
    @Published public private(set) var threads: [AgentThread] = []
    @Published public private(set) var messages: [AgentMessage] = []
    @Published public private(set) var currentThreadID: UUID?
    @Published public private(set) var isThinking = false
    @Published public private(set) var lastError: String?

    public let voiceCapture: AgentVoiceCapture?

    private let runtime: AgentRuntime
    private let threadStore: AgentThreadStore
    private let messageStore: AgentMessageStore
    private let memoryStore: AgentMemoryStore

    public init(
        runtime: AgentRuntime,
        threadStore: AgentThreadStore,
        messageStore: AgentMessageStore,
        memoryStore: AgentMemoryStore,
        voiceCapture: AgentVoiceCapture? = nil
    ) {
        self.runtime = runtime
        self.threadStore = threadStore
        self.messageStore = messageStore
        self.memoryStore = memoryStore
        self.voiceCapture = voiceCapture

        reloadThreads()
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
                    scope: "global"
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
