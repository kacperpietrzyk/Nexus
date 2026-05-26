import Foundation

public struct AgentTurnRequest: Sendable {
    public let threadID: UUID
    public let userMessage: String
    public let attachments: [String]
    public let contextPrefix: String?
    public let scope: String
    public let providerHint: String?

    public init(
        threadID: UUID,
        userMessage: String,
        attachments: [String] = [],
        contextPrefix: String? = nil,
        scope: String,
        providerHint: String? = nil
    ) {
        self.threadID = threadID
        self.userMessage = userMessage
        self.attachments = attachments
        self.contextPrefix = contextPrefix
        self.scope = scope
        self.providerHint = providerHint
    }
}
