import Foundation

public struct AgentTurnRequest: Sendable {
    public let threadID: UUID
    public let userMessage: String
    public let attachments: [String]
    public let contextPrefix: String?
    public let scope: String
    public let providerHint: String?
    /// When non-nil, only tools whose `name` is in this list are exposed to the
    /// model (both in the flat-prompt `toolDefinitionsJSON` and in the structured
    /// `AIRequest.tools` surface). `nil` preserves full-registry behaviour.
    public let toolAllowlist: [String]?
    /// When non-nil, replaces the `ContextBuilder`'s default system prompt for this
    /// turn only. Used by `assistant.chat` to inject the persona + proposal-block
    /// instruction without touching the global ContextBuilder configuration.
    public let systemPromptOverride: String?

    public init(
        threadID: UUID,
        userMessage: String,
        attachments: [String] = [],
        contextPrefix: String? = nil,
        scope: String,
        providerHint: String? = nil,
        toolAllowlist: [String]? = nil,
        systemPromptOverride: String? = nil
    ) {
        self.threadID = threadID
        self.userMessage = userMessage
        self.attachments = attachments
        self.contextPrefix = contextPrefix
        self.scope = scope
        self.providerHint = providerHint
        self.toolAllowlist = toolAllowlist
        self.systemPromptOverride = systemPromptOverride
    }
}
