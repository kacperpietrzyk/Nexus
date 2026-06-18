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
    /// High-level project type (universal types extension). Raw `ProjectType`;
    /// existing/pre-V15 rows default to `.generic`. Drives stage preset + default
    /// sections + which fields the UI surfaces. Additive/defaulted ⇒ lightweight migration.
    public var typeRaw: String = ProjectType.generic.rawValue
    /// Current granular stage within this type's preset (raw `ProjectStage`). nil =
    /// not placed on the pipeline. Kept in sync with `statusRaw` via the repository.
    public var stageRaw: String?
    /// Client/account this project is for (→ `Organization.id`). nil for internal/dev.
    public var clientID: UUID?
    /// Vendor / product line, free text for v1 (e.g. "Proofpoint DLP").
    public var vendor: String?
    /// JSON-encoded `[String:String]` custom-field bag (long-tail metadata: dealValue,
    /// sku, competitor, scopeSource). CloudKit-safe (String). NOTE: bag values are not
    /// queryable/sortable — promote to first-class fields later if reporting needs it.
    public var customFieldsJSON: String?
    /// Pointer to the project's canonical page `Note` (`role == .projectPage`).
    /// nil = no page yet (Notes content layer, spec §4.2). Additive/optional.
    public var canonicalNoteRef: UUID?
    public var archivedAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?
    /// Whether the user has pinned this project to the Today dashboard.
    /// Additive/defaulted — CloudKit-safe lightweight migration.
    public var isPinned: Bool = false
    /// When the project was most recently pinned. nil if never pinned.
    public var pinnedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        color: String = "azure",
        parentProjectID: UUID? = nil,
        status: ProjectStatus = .backlog,
        type: ProjectType = .generic
    ) {
        self.id = id
        self.kind = .project
        self.name = name
        self.color = color
        self.parentProjectID = parentProjectID
        self.statusRaw = status.rawValue
        self.typeRaw = type.rawValue
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

    /// Read/write view over `typeRaw`. Unknown stored raw ⇒ `.generic`.
    public var type: ProjectType {
        get { ProjectType(rawValue: typeRaw) ?? .generic }
        set { typeRaw = newValue.rawValue }
    }

    /// Read/write view over `stageRaw`. nil when not placed on the pipeline.
    public var stage: ProjectStage? {
        get { stageRaw.flatMap(ProjectStage.init(rawValue:)) }
        set { stageRaw = newValue?.rawValue }
    }

    /// Read/write view over `customFieldsJSON`. Decode failure ⇒ empty dict.
    public var customFields: [String: String] {
        get {
            guard let data = customFieldsJSON?.data(using: .utf8),
                let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                customFieldsJSON = nil
                return
            }
            customFieldsJSON = String(data: data, encoding: .utf8)
        }
    }

    public var searchableText: String { name }
}
