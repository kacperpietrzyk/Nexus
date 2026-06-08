import Foundation
import SwiftData

@Model
public final class Project: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.project
    public var name: String = ""
    /// Stores a legacy shape-token name (azure/gold/emerald/rose/violet/slate), retained to avoid
    /// schema migration. Since MP-2.1 slice 3c the value is a glyph key consumed via
    /// `nexusProjectGlyph(named:)` in TasksFeature; no color is rendered from it.
    public var color: String = "azure"
    public var parentProjectID: UUID?
    /// Lifecycle state machine (Projects tier, spec §4.1; `ProjectStatus` raw).
    /// Stored as `String` because SwiftData + CloudKit reject enum-typed
    /// properties. Defaults to `backlog`; read through the `status` accessor.
    /// Orthogonal to `archivedAt` (a completed/cancelled project may or may not
    /// be archived). Additive — defaulted so it flows into V9/V10 as lightweight.
    public var statusRaw: String = ProjectStatus.backlog.rawValue
    /// Pointer to the project's canonical page `Note` (`role == .projectPage`).
    /// nil = no page yet (Notes content layer, spec §4.2). Additive/optional.
    public var canonicalNoteRef: UUID?
    public var archivedAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        color: String = "azure",
        parentProjectID: UUID? = nil,
        status: ProjectStatus = .backlog
    ) {
        self.id = id
        self.kind = .project
        self.name = name
        self.color = color
        self.parentProjectID = parentProjectID
        self.statusRaw = status.rawValue
        self.archivedAt = nil
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    /// Get-only view over `statusRaw` (Projects tier, spec §4.1). Falls back to
    /// `backlog` for an unknown stored raw.
    public var status: ProjectStatus {
        ProjectStatus(rawValue: statusRaw) ?? .backlog
    }

    public var searchableText: String { name }
}
