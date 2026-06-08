import Foundation
import SwiftData

/// A lightweight single-user contact RECORD (People / Contacts module, spec §4.1) —
/// like a row in Apple Contacts, **not** a user account. `Person` aggregates
/// "everything about a person" (meetings, mentioned tasks/notes) purely through the
/// polymorphic `Link` graph; it is never a task assignee and is orthogonal to
/// `AgentAssignee` (invariant I1, spec §5).
///
/// Partitioned as **synced** (CloudKit `.private`), so every stored property carries a
/// default value (CloudKit mirroring requires it) and `kind` is fixed to `.person`.
/// Raw enum values on `kind` are CloudKit-bound and MUST NEVER be renamed without a
/// migration. Soft-delete via `deletedAt`. Identity / dedup is keyed on
/// `externalSourceID` (idempotent import) with a `displayName` + `aliases` soft-match
/// fallback (spec §4.3).
@Model
public final class Person: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.person
    public var displayName: String = ""
    /// Name/alias variants used for dedup soft-matching (case/diacritic-insensitive).
    public var aliases: [String] = []
    public var email: String?
    public var phone: String?
    /// Company is a plain field, NOT a separate `Organization` entity (spec §2 OUT).
    public var company: String?
    /// Short free-form contact note. A rich biography belongs in a backing Note
    /// (Notes content layer), not here (spec §4.1).
    public var note: String?
    /// Idempotent-import key (e.g. `"calendar-attendee:<email>"`). Same value ⇒ UPDATE,
    /// not a duplicate (spec §4.3). nil for manually-created people.
    public var externalSourceID: String?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        aliases: [String] = [],
        email: String? = nil,
        phone: String? = nil,
        company: String? = nil,
        note: String? = nil,
        externalSourceID: String? = nil
    ) {
        self.id = id
        self.kind = .person
        self.displayName = displayName
        self.aliases = aliases
        self.email = email
        self.phone = phone
        self.company = company
        self.note = note
        self.externalSourceID = externalSourceID
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    /// `Linkable` requires a settable `title`; for a `Person` it is the display name.
    public var title: String {
        get { displayName }
        set { displayName = newValue }
    }

    /// Searchable text = display name + aliases + company (spec §4.1 / §9).
    public var searchableText: String {
        ([displayName] + aliases + [company].compactMap { $0 })
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
