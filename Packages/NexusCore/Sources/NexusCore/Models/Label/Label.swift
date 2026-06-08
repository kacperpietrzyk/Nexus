import Foundation
import SwiftData

/// A structural label (Projects tier, spec §4.4). Labels attach to tasks and
/// projects via the `Link` graph (`LinkKind.labeled`) — never via SwiftData
/// `@Relationship` (decision D7). Labels are partitioned as **synced** (like
/// `TaskItem`), so they travel with the user's data.
///
/// The group (`groupRaw` → `LabelGroup`) drives the single-select policy enforced
/// in `LabelRepository` (invariant I5). `isSystem` marks seeded labels
/// (feature/bug/infra/security; needsDecision/decided) that the UI must not
/// delete. Achromatic per LabKit: identity is a `glyphKey` (a glyph), not a color.
///
/// `kind` is fixed to `.label`; raw enum values on `kind`/`groupRaw` are
/// CloudKit-bound and MUST NEVER be renamed without a migration. Soft-delete via
/// `deletedAt`.
@Model
public final class Label: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.label
    public var name: String = ""
    /// Achromatic glyph identifier (LabKit) — never a color. Consumed by the UI
    /// layer to render the label's sigil.
    public var glyphKey: String = ""
    /// `LabelGroup` raw value (domain/gate/free). Read through the `group`
    /// accessor. Stored as `String` because SwiftData + CloudKit reject
    /// enum-typed properties.
    public var groupRaw: String = LabelGroup.free.rawValue
    /// `true` for seeded system labels (non-deletable from the UI); `false` for
    /// user-created labels.
    public var isSystem: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        glyphKey: String = "",
        group: LabelGroup = .free,
        isSystem: Bool = false
    ) {
        self.id = id
        self.kind = .label
        self.name = name
        self.glyphKey = glyphKey
        self.groupRaw = group.rawValue
        self.isSystem = isSystem
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    /// Get-only view over `groupRaw` (spec §4.4). Falls back to `free` for an
    /// unknown stored raw.
    public var group: LabelGroup {
        LabelGroup(rawValue: groupRaw) ?? .free
    }

    /// Labels are searchable by name (spec §14).
    public var searchableText: String { name }
}
