import Foundation
import SwiftData

/// CRUD + idempotent creation + backlink/outgoing queries on `Link`.
/// Note: `Link` is NOT `Linkable` (it's an edge, not a node), so it gets its own repo.
@MainActor
public final class LinkRepository {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func create(
        from: (ItemKind, UUID),
        to: (ItemKind, UUID),
        linkKind: LinkKind,
        order: Int? = nil
    ) throws -> Link {
        let link = Link(from: from, to: to, linkKind: linkKind, order: order)
        context.insert(link)
        try context.save()
        return link
    }

    /// Idempotent: returns the existing link with the same endpoints+kind, or creates a new one.
    /// Implemented predicate-side rather than via `@Attribute(.unique)` because CloudKit forbids
    /// uniqueness constraints (`#Unique` is incompatible).
    @discardableResult
    public func findOrCreate(
        from: (ItemKind, UUID),
        to: (ItemKind, UUID),
        linkKind: LinkKind,
        order: Int? = nil
    ) throws -> Link {
        let fromID = from.1
        let toID = to.1
        // SwiftData #Predicate cannot capture enum values at runtime, so we pre-filter by UUIDs
        // (which are functionally unique) and refine the match in-memory.
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in
                link.fromID == fromID && link.toID == toID
            }
        )
        if let existing = try context.fetch(descriptor).first(where: {
            $0.fromKind == from.0 && $0.toKind == to.0 && $0.linkKind == linkKind
        }) {
            return existing
        }
        return try create(from: from, to: to, linkKind: linkKind, order: order)
    }

    public func backlinks(to endpoint: (ItemKind, UUID)) throws -> [Link] {
        let kind = endpoint.0
        let id = endpoint.1
        // NOTE: the kind filter stays in Swift. SwiftData's predicate→SQL translator
        // rejects an enum-rawValue keypath (`\Link.toKind.rawValue` traps at fetch:
        // "rawValue is not a member of ItemKind"), and `Link` stores `toKind` as the
        // enum itself with no raw-String column. Pushing the discriminator into SQLite
        // would require a `@Model` schema change (a new stored `toKindRaw`), which is
        // out of scope (CloudKit/migration risk). Fan-out is killed by the batched
        // `backlinks(toKind:toIDs:)` fetch instead; per-endpoint it's a small scan.
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in link.toID == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).dedupedByID().filter { $0.toKind == kind }
    }

    public func outgoing(from endpoint: (ItemKind, UUID)) throws -> [Link] {
        let kind = endpoint.0
        let id = endpoint.1
        // See `backlinks(to:)` — the enum-rawValue predicate isn't translatable by
        // SwiftData, so kind discrimination stays in Swift; the N+1 storm is removed
        // by the batched `outgoing(fromKind:fromIDs:)` fetch.
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in link.fromID == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).dedupedByID().filter { $0.fromKind == kind }
    }

    /// Batched form of ``outgoing(from:)``: resolves outgoing links for MANY
    /// endpoints of the same `fromKind` in ONE fetch, returning a `[fromID: [Link]]`
    /// grouping. For each id the resulting array is byte-for-byte identical to
    /// `outgoing(from: (fromKind, id))` — same links, same `createdAt`-reverse order.
    /// Replaces the N+1 per-endpoint fetch storm on the Today screen.
    public func outgoing(fromKind: ItemKind, fromIDs: [UUID]) throws -> [UUID: [Link]] {
        let idSet = Set(fromIDs)
        guard !idSet.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in idSet.contains(link.fromID) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // One sorted fetch; group by fromID after the in-Swift kind filter. SwiftData
        // preserves the descriptor sort across the whole result set, so each per-id
        // slice keeps createdAt-reverse order — matching the single-endpoint method.
        return Dictionary(
            grouping: try context.fetch(descriptor).filter { $0.fromKind == fromKind },
            by: \.fromID
        )
    }

    /// Batched form of ``backlinks(to:)``: resolves incoming links for MANY
    /// endpoints of the same `toKind` in ONE fetch, returning a `[toID: [Link]]`
    /// grouping. For each id the resulting array is byte-for-byte identical to
    /// `backlinks(to: (toKind, id))`.
    public func backlinks(toKind: ItemKind, toIDs: [UUID]) throws -> [UUID: [Link]] {
        let idSet = Set(toIDs)
        guard !idSet.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in idSet.contains(link.toID) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return Dictionary(
            grouping: try context.fetch(descriptor).filter { $0.toKind == toKind },
            by: \.toID
        )
    }

    public func outgoingBlocks(from endpoint: (ItemKind, UUID)) throws -> [Link] {
        try outgoing(from: endpoint).filter { $0.linkKind == .blocks }
    }

    public func incomingBlocks(to endpoint: (ItemKind, UUID)) throws -> [Link] {
        try backlinks(to: endpoint).filter { $0.linkKind == .blocks }
    }

    /// Every `Link` row, oldest first. The O1 graph view consumes the whole
    /// edge table in one fetch; deterministic `createdAt` order keeps graph
    /// assembly reproducible. No kind filter is needed, so no enum lands in
    /// the predicate.
    public func allLinks() throws -> [Link] {
        try context.fetch(
            FetchDescriptor<Link>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
        )
    }

    public func delete(_ link: Link) throws {
        context.delete(link)
        try context.save()
    }
}
