import Foundation
import NexusCore

public struct SectionDTO: Codable, Sendable, Equatable {
    public let id: String
    public let projectID: String
    public let name: String
    public let orderIndex: Double
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case name
        case orderIndex = "order_index"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from section: Section) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = section.id.uuidString
        self.projectID = section.projectID.uuidString
        self.name = section.name
        self.orderIndex = section.orderIndex
        self.createdAt = formatter.string(from: section.createdAt)
        self.updatedAt = formatter.string(from: section.updatedAt)
    }
}
