import Foundation

public struct InboxItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceID: String
    public let title: String
    public let body: String?
    public let due: Date?
    public let tags: [String]
    public let createdAt: Date

    public init(
        id: UUID,
        sourceID: String,
        title: String,
        body: String?,
        due: Date?,
        tags: [String],
        createdAt: Date
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.body = body
        self.due = due
        self.tags = tags
        self.createdAt = createdAt
    }
}
