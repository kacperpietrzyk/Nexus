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

    // MARK: Universal-type fields (Projects tier, spec §4 — universal types extension)

    /// `ProjectType` raw value (e.g. `"implementation"`, `"sales"`, `"audit"`,
    /// `"internalDev"`, `"generic"`). Pre-V15 projects read back as `"generic"`.
    public let type: String
    /// `ProjectStage` raw value when set; `nil` for `.generic` projects or when no
    /// stage has been assigned yet.
    public let stage: String?
    /// UUID of the linked `Organization` acting as this project's client, if any.
    public let clientID: UUID?
    /// Free-form vendor / partner name, if any.
    public let vendor: String?
    /// Arbitrary key-value metadata set by the user or agent (spec §4.3).
    public let customFields: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id, name, status, glyph, sections, type, stage, vendor
        case canonicalNoteID = "canonical_note_id"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case taskCount = "task_count"
        case clientID = "client_id"
        case customFields = "custom_fields"
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
        taskCount: Int? = nil,
        type: String = "generic",
        stage: String? = nil,
        clientID: UUID? = nil,
        vendor: String? = nil,
        customFields: [String: String] = [:]
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
        self.type = type
        self.stage = stage
        self.clientID = clientID
        self.vendor = vendor
        self.customFields = customFields
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
            updatedAt: formatter.string(from: project.updatedAt),
            type: project.type.rawValue,
            stage: project.stage?.rawValue,
            clientID: project.clientID,
            vendor: project.vendor,
            customFields: project.customFields
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
            taskCount: taskCount,
            type: project.type.rawValue,
            stage: project.stage?.rawValue,
            clientID: project.clientID,
            vendor: project.vendor,
            customFields: project.customFields
        )
    }
}
