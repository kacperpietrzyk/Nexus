import Foundation
import SwiftData

public final class AgentMessageStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func append(
        threadID: UUID,
        role: AgentMessageRole,
        content: String,
        toolCallJSON: Data? = nil,
        attachments: [String] = [],
        tokensIn: Int = 0,
        tokensOut: Int = 0,
        providerID: String = "",
        now: Date = .now
    ) throws -> UUID {
        let message = AgentMessage(
            threadID: threadID,
            createdAt: now,
            role: role,
            content: content,
            toolCallJSON: toolCallJSON,
            attachments: attachments,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            providerID: providerID
        )
        context.insert(message)
        try context.save()
        return message.id
    }

    /// Overwrites the persisted `content` of the message with the given `id`.
    /// Used after a turn to strip the raw `nexus-proposal` block from the stored
    /// assistant message so history never exposes it (proposal-block-leak landmine).
    public func overwriteContent(id: UUID, content: String) throws {
        var descriptor = FetchDescriptor<AgentMessage>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let message = try context.fetch(descriptor).first else { return }
        message.content = content
        try context.save()
    }

    public func slidingWindow(threadID: UUID, last n: Int) throws -> [AgentMessage] {
        guard n > 0 else { return [] }

        var descriptor = FetchDescriptor<AgentMessage>(
            predicate: #Predicate { $0.threadID == threadID },
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse),
            ]
        )
        descriptor.fetchLimit = n
        let recent = try context.fetch(descriptor)
        return Array(recent.reversed())
    }
}
