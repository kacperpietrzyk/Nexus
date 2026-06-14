import Foundation
import SwiftData

/// A client / account record (universal-types extension) — the customer a sales or
/// implementation `Project` is for (e.g. "AKMF", "Volkswagen Poznań"). Distinct from
/// `Person` (a human contact); People attach to an Organization via the `Link` graph,
/// and `Project.clientID` points here by raw id.
///
/// Partitioned as **synced** (CloudKit `.private`), so every stored property carries a
/// default value and `kind` is fixed to `.organization` (raw values CloudKit-bound —
/// never rename without a migration). Soft-delete via `deletedAt`. `Person.company`
/// stays as a denormalized convenience field and is not authoritative once linked.
@Model
public final class Organization: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.organization
    public var name: String = ""
    public var sector: String?
    /// Name/alias variants for dedup soft-matching (mirrors `Person`).
    public var aliases: [String] = []
    /// Idempotent-import key; nil for manually-created orgs.
    public var externalSourceID: String?
    /// Short free-form note; a rich profile belongs in a backing `Note`.
    public var note: String?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        sector: String? = nil,
        externalSourceID: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = .organization
        self.name = name
        self.aliases = aliases
        self.sector = sector
        self.externalSourceID = externalSourceID
        self.note = note
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// `Linkable` requires a settable `title`; for an `Organization` it is the name.
    public var title: String {
        get { name }
        set { name = newValue }
    }

    /// Searchable text = name + aliases + sector (mirrors `Person`).
    public var searchableText: String {
        ([name] + aliases + [sector].compactMap { $0 }).joined(separator: " ")
    }
}
