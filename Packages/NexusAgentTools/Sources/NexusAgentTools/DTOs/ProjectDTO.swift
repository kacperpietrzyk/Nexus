import Foundation
import NexusCore

/// Wire format for `Project` exposed via MCP (Projects tier, spec §10). snake_case
/// keys per MCP convention. `status` is the `ProjectStatus` raw value; `glyph` is the
/// achromatic glyph key (persisted on `Project.color`, repurposed as a glyph key since
/// MP-2.1 — never a literal color).
public struct ProjectDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let status: String
    public let glyph: String
    public let canonicalNoteID: String?
    public let archivedAt: String?
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, status, glyph
        case canonicalNoteID = "canonical_note_id"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        name: String,
        status: String,
        glyph: String,
        canonicalNoteID: String?,
        archivedAt: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.glyph = glyph
        self.canonicalNoteID = canonicalNoteID
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from project: Project) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: project.id.uuidString,
            name: project.name,
            status: project.status.rawValue,
            glyph: project.color,
            canonicalNoteID: project.canonicalNoteRef?.uuidString,
            archivedAt: project.archivedAt.map { formatter.string(from: $0) },
            createdAt: formatter.string(from: project.createdAt),
            updatedAt: formatter.string(from: project.updatedAt)
        )
    }
}
