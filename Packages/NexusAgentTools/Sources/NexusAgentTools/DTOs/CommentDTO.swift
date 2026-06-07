import Foundation
import NexusCore

/// A serialisable snapshot of a `Comment` for MCP tool responses.
public struct CommentDTO: Codable, Sendable, Equatable {
    public let id: String
    public let itemID: String
    public let itemKind: String
    public let body: String
    public let createdAt: String
    public let updatedAt: String
    public let externalSourceID: String?

    private enum CodingKeys: String, CodingKey {
        case id, body
        case itemID = "item_id"
        case itemKind = "item_kind"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case externalSourceID = "external_source_id"
    }

    @MainActor
    public init(from comment: Comment) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = comment.id.uuidString
        self.itemID = comment.itemID.uuidString
        self.itemKind = comment.itemKind.rawValue
        self.body = comment.body
        self.createdAt = formatter.string(from: comment.createdAt)
        self.updatedAt = formatter.string(from: comment.updatedAt)
        self.externalSourceID = comment.externalSourceID
    }
}
