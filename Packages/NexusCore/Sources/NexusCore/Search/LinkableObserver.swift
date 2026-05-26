import Foundation

/// Sendable snapshot of a `Searchable` item, extracted on the model's owning actor
/// (typically `@MainActor` for SwiftData) before being posted to observers across
/// isolation boundaries. Observers only ever see this — never the live `@Model` row.
public struct IndexedDocument: Sendable, Equatable, Hashable {
    public let kind: ItemKind
    public let id: UUID
    public let text: String
    public let updatedAt: Date

    public init(kind: ItemKind, id: UUID, text: String, updatedAt: Date) {
        self.kind = kind
        self.id = id
        self.text = text
        self.updatedAt = updatedAt
    }

    /// Convenience initializer that snapshots a live `Searchable` row. Must be called
    /// on the actor that owns the row (caller's responsibility — typically `@MainActor`).
    public init<S: Searchable>(_ item: S) {
        self.kind = item.kind
        self.id = item.id
        self.text = item.searchableText
        self.updatedAt = item.updatedAt
    }
}

/// Receives upsert / soft-delete events emitted by `LinkableRepository`. Both `SearchIndex`
/// and `SpotlightIndexer` conform — repository fans out to every registered observer.
///
/// Observers MUST be `Sendable` and all methods are `async` so the repository can dispatch
/// fan-out without blocking its `@MainActor` context.
///
/// Phase 0d intentionally does NOT define `didPurge(kind:id:)` — `TombstonePurger` doesn't
/// route through this protocol today. When the purger needs to evict from Spotlight (Phase 1+),
/// add the method here and update both conformers.
public protocol LinkableObserver: Sendable {
    func didUpsert(_ document: IndexedDocument) async
    func didSoftDelete(kind: ItemKind, id: UUID) async
}
