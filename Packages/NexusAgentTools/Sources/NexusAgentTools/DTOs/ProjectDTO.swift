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
    /// Populated only by the enriching `init(from:sections:taskCount:)` (used by
    /// `projects.get` for discovery); `nil` for the bare list/create DTOs.
    public let sections: [SectionDTO]?
    public let taskCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, status, glyph, sections
        case canonicalNoteID = "canonical_note_id"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case taskCount = "task_count"
    }

    public init(
        id: String,
        name: String,
        status: String,
        glyph: String,
        canonicalNoteID: String?,
        archivedAt: String?,
        createdAt: String,
        updatedAt: String,
        sections: [SectionDTO]? = nil,
        taskCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.glyph = glyph
        self.canonicalNoteID = canonicalNoteID
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sections = sections
        self.taskCount = taskCount
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

    /// Enriched form for `projects.get`: includes the project's live sections and a
    /// task count for discovery. Mirrors `init(from:)`'s scalar mapping, then fills
    /// the discovery fields (a `let`-reassign after delegation isn't allowed, so the
    /// scalar copies are inlined rather than delegated).
    public init(from project: Project, sections: [Section], taskCount: Int) {
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
            updatedAt: formatter.string(from: project.updatedAt),
            sections: sections.map(SectionDTO.init(from:)),
            taskCount: taskCount
        )
    }
}
