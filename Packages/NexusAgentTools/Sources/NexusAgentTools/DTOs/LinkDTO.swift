import Foundation
import NexusCore

public struct LinkDTO: Codable, Sendable, Equatable {
    public let id: String
    public let fromID: String
    public let fromKind: String
    public let toID: String
    public let toKind: String
    public let linkKind: String
    public let order: Int?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case fromID = "from_id"
        case fromKind = "from_kind"
        case toID = "to_id"
        case toKind = "to_kind"
        case linkKind = "link_kind"
        case order
        case createdAt = "created_at"
    }

    public init(from link: Link) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = link.id.uuidString
        self.fromID = link.fromID.uuidString
        self.fromKind = link.fromKind.rawValue
        self.toID = link.toID.uuidString
        self.toKind = link.toKind.rawValue
        self.linkKind = link.linkKind.rawValue
        self.order = link.order
        self.createdAt = formatter.string(from: link.createdAt)
    }
}
