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
        // TODO(phase-1): when Link table grows past hundreds of rows per endpoint,
        // switch to a rawValue string predicate (e.g. let rawKind = kind.rawValue;
        // #Predicate { $0.toKind.rawValue == rawKind }) — pushes kind discrimination
        // back into SQLite and removes the in-memory scan.
        // SwiftData #Predicate cannot capture enum values; pre-filter by UUID, refine in-memory.
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in link.toID == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.toKind == kind }
    }

    public func outgoing(from endpoint: (ItemKind, UUID)) throws -> [Link] {
        let kind = endpoint.0
        let id = endpoint.1
        // TODO(phase-1): when Link table grows past hundreds of rows per endpoint,
        // switch to a rawValue string predicate (e.g. let rawKind = kind.rawValue;
        // #Predicate { $0.fromKind.rawValue == rawKind }) — pushes kind discrimination
        // back into SQLite and removes the in-memory scan.
        // SwiftData #Predicate cannot capture enum values; pre-filter by UUID, refine in-memory.
        let descriptor = FetchDescriptor<Link>(
            predicate: #Predicate { link in link.fromID == id },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).filter { $0.fromKind == kind }
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
