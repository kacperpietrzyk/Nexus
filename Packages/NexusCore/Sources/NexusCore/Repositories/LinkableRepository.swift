import Foundation
import SwiftData

/// Generic CRUD on any `Linkable` type. Bound to a single `ModelContext`; never share across actors.
///
/// **Observer fan-out (Phase 0d):** if the caller passes a non-empty `observers` list, the repo
/// fires `didUpsert` (after `insert` / `restore`) and `didSoftDelete` (after `softDelete`).
/// Fan-out runs in detached `Task`s so the repository's `@MainActor` context is never blocked
/// by an observer awaiting actor isolation. The `Sendable` `IndexedDocument` payload is
/// constructed *on the main actor* (where the model row is safe to read), then passed across.
///
/// Observer fan-out for `didUpsert` requires `Item: Searchable` (we need `searchableText`).
/// Plain `Linkable` items can still use the repo — they just don't generate upsert events
/// (in practice every concrete model in Nexus conforms to `Searchable`).
@MainActor
public final class LinkableRepository<Item: Linkable> {
    public let context: ModelContext
    public let observers: [any LinkableObserver]

    public init(context: ModelContext, observers: [any LinkableObserver] = []) {
        self.context = context
        self.observers = observers
    }

    public func insert(_ item: Item) throws {
        context.insert(item)
        try context.save()
        broadcastUpsert(for: item)
    }

    public func find(id: UUID) throws -> Item? {
        // Filter in Swift rather than via a `#Predicate<Item>`: an `$0.id == id` keypath
        // built over the generic protocol type `Item` synthesizes a `\Item.id` keypath through
        // the `Linkable` witness that SwiftData cannot match against the concrete model's
        // registered schema keypath in optimized (Release) builds — same `DataUtilities` trap
        // as `fetchAll()`. Fetching and matching in memory avoids keypath translation.
        try context.fetch(FetchDescriptor<Item>()).first { $0.id == id }
    }

    /// Returns all live (non-tombstoned) items.
    public func fetchAll() throws -> [Item] {
        // Fetch every row and filter/sort in Swift rather than via a `#Predicate<Item>` /
        // generic `SortDescriptor`. A predicate or sort keypath built over the generic protocol
        // type `Item` synthesizes a keypath through the `Linkable` witness that SwiftData cannot
        // match against the concrete model's registered schema keypath in optimized (Release)
        // builds — it traps in `DataUtilities` with "Couldn't find \Model.<computed …>". Fetching
        // all and filtering/sorting in memory avoids keypath translation entirely; tombstone
        // volume is bounded by `TombstonePurger`, so the cost is negligible at single-user scale.
        try context.fetch(FetchDescriptor<Item>())
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Returns everything, including tombstones. Used by `TombstonePurger` and admin tools.
    public func fetchAllIncludingDeleted() throws -> [Item] {
        try context.fetch(FetchDescriptor<Item>())
    }

    public func softDelete(_ item: Item) throws {
        let now = Date.now
        item.deletedAt = now
        item.updatedAt = now
        try context.save()
        let kind = item.kind
        let id = item.id
        for observer in observers {
            _Concurrency.Task { await observer.didSoftDelete(kind: kind, id: id) }
        }
    }

    public func restore(_ item: Item) throws {
        item.deletedAt = nil
        item.updatedAt = .now
        try context.save()
        broadcastUpsert(for: item)
    }

    private func broadcastUpsert(for item: Item) {
        guard !observers.isEmpty else { return }
        guard let searchable = item as? any Searchable else {
            // Plain Linkable — no searchableText, so no upsert event in 0d.
            // (Every real Nexus model conforms to Searchable; this branch is defensive.)
            return
        }
        let document = makeDocument(searchable)
        for observer in observers {
            _Concurrency.Task { await observer.didUpsert(document) }
        }
    }

    private func makeDocument(_ item: any Searchable) -> IndexedDocument {
        IndexedDocument(
            kind: item.kind,
            id: item.id,
            text: item.searchableText,
            updatedAt: item.updatedAt
        )
    }
}
