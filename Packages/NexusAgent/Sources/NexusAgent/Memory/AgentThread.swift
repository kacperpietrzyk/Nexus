import Foundation
import SwiftData

@Model
public final class AgentThread {
    public var id: UUID = UUID()
    public var title: String = ""
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var archivedAt: Date?
    public var projectID: UUID?
    public var modelHint: String?

    public init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil,
        projectID: UUID? = nil,
        modelHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.projectID = projectID
        self.modelHint = modelHint
    }
}
