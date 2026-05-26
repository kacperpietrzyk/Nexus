import Foundation
import SwiftData

public enum AgentMessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case agent
    case tool
    case system
}

@Model
public final class AgentMessage {
    public var id: UUID = UUID()
    public var threadID: UUID = UUID()
    public var createdAt: Date = Date.now
    public var roleRaw: String = AgentMessageRole.system.rawValue
    public var content: String = ""
    public var toolCallJSON: Data?
    public var attachments: [String] = []
    public var tokensIn: Int = 0
    public var tokensOut: Int = 0
    public var providerID: String = ""
    public var redactedContent: Bool = false

    public var role: AgentMessageRole {
        get { AgentMessageRole(rawValue: roleRaw) ?? .system }
        set { roleRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        createdAt: Date = .now,
        role: AgentMessageRole,
        content: String,
        toolCallJSON: Data? = nil,
        attachments: [String] = [],
        tokensIn: Int = 0,
        tokensOut: Int = 0,
        providerID: String = "",
        redactedContent: Bool = false
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.roleRaw = role.rawValue
        self.content = content
        self.toolCallJSON = toolCallJSON
        self.attachments = attachments
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.providerID = providerID
        self.redactedContent = redactedContent
    }
}
