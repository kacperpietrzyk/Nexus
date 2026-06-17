import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Test func linkRepository_create_persistsLink() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let from = UUID()
    let to = UUID()
    let link = try repo.create(from: (.task, from), to: (.meeting, to), linkKind: .source)
    #expect(link.fromID == from)
    #expect(link.toID == to)

    let all = try context.fetch(FetchDescriptor<Link>())
    #expect(all.count == 1)
}

@MainActor
@Test func linkRepository_findOrCreate_isIdempotent() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    let from = UUID()
    let to = UUID()

    let a = try repo.findOrCreate(from: (.task, from), to: (.meeting, to), linkKind: .actionItem)
    let b = try repo.findOrCreate(from: (.task, from), to: (.meeting, to), linkKind: .actionItem)

    #expect(a.id == b.id)
    let all = try context.fetch(FetchDescriptor<Link>())
    #expect(all.count == 1)
}

@MainActor
@Test func linkRepository_backlinks_returnsAllLinksToTarget() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let target = UUID()
    let source1 = UUID()
    let source2 = UUID()

    _ = try repo.create(from: (.note, source1), to: (.task, target), linkKind: .mentions)
    _ = try repo.create(from: (.meeting, source2), to: (.task, target), linkKind: .source)

    let backlinks = try repo.backlinks(to: (.task, target))
    #expect(backlinks.count == 2)
    let kinds = Set(backlinks.map(\.linkKind))
    #expect(kinds == [.mentions, .source])
}

@MainActor
@Test func linkRepository_outgoing_returnsAllLinksFromSource() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let source = UUID()
    _ = try repo.create(from: (.task, source), to: (.meeting, UUID()), linkKind: .source)
    _ = try repo.create(from: (.task, source), to: (.note, UUID()), linkKind: .mentions)

    let outgoing = try repo.outgoing(from: (.task, source))
    #expect(outgoing.count == 2)
}

@MainActor
@Test func linkRepository_delete_removesLink() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let link = try repo.create(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions)
    try repo.delete(link)

    let all = try context.fetch(FetchDescriptor<Link>())
    #expect(all.isEmpty)
}

@MainActor
@Test func linkRepository_findOrCreate_treatsDifferentLinkKindAsNewLink() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    let from = UUID()
    let to = UUID()

    let mentions = try repo.findOrCreate(from: (.task, from), to: (.meeting, to), linkKind: .mentions)
    let source = try repo.findOrCreate(from: (.task, from), to: (.meeting, to), linkKind: .source)

    #expect(mentions.id != source.id)
    let all = try context.fetch(FetchDescriptor<Link>())
    #expect(all.count == 2)
}

@MainActor
@Test func linkRepository_backlinks_excludesMismatchedToKind() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let target = UUID()
    // Both links share `target` as their toID, but only one has toKind == .task.
    _ = try repo.create(from: (.note, UUID()), to: (.task, target), linkKind: .mentions)
    _ = try repo.create(from: (.meeting, UUID()), to: (.note, target), linkKind: .mentions)

    let backlinks = try repo.backlinks(to: (.task, target))
    #expect(backlinks.count == 1)
    #expect(backlinks.first?.toKind == .task)
}

@MainActor
@Test func linkRepository_outgoing_excludesMismatchedFromKind() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let source = UUID()
    // Both links share `source` as their fromID, but only one has fromKind == .task.
    _ = try repo.create(from: (.task, source), to: (.meeting, UUID()), linkKind: .source)
    _ = try repo.create(from: (.note, source), to: (.task, UUID()), linkKind: .mentions)

    let outgoing = try repo.outgoing(from: (.task, source))
    #expect(outgoing.count == 1)
    #expect(outgoing.first?.fromKind == .task)
}

@MainActor
@Test func linkRepository_outgoingBlocks_filtersByBlocksKind() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    let source = UUID()
    let blocked = UUID()
    _ = try repo.create(from: (.task, source), to: (.task, blocked), linkKind: .blocks)
    _ = try repo.create(from: (.task, source), to: (.note, UUID()), linkKind: .mentions)

    let outgoing = try repo.outgoingBlocks(from: (.task, source))
    #expect(outgoing.count == 1)
    #expect(outgoing.first?.toID == blocked)
    #expect(outgoing.first?.linkKind == .blocks)
}

@MainActor
@Test func linkRepository_incomingBlocks_returnsReverseEdges() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    let target = UUID()
    let upstream1 = UUID()
    let upstream2 = UUID()
    _ = try repo.create(from: (.task, upstream1), to: (.task, target), linkKind: .blocks)
    _ = try repo.create(from: (.task, upstream2), to: (.task, target), linkKind: .blocks)
    _ = try repo.create(from: (.note, UUID()), to: (.task, target), linkKind: .mentions)

    let incoming = try repo.incomingBlocks(to: (.task, target))
    #expect(incoming.count == 2)
    #expect(Set(incoming.map(\.fromID)) == [upstream1, upstream2])
}

@MainActor
@Test func linkRepository_allLinks_returnsEveryEdgeOldestFirst() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let first = try repo.create(from: (.note, UUID()), to: (.task, UUID()), linkKind: .mentions)
    let second = try repo.create(from: (.task, UUID()), to: (.project, UUID()), linkKind: .child)
    let third = try repo.create(from: (.meeting, UUID()), to: (.person, UUID()), linkKind: .attendee)

    let all = try repo.allLinks()
    #expect(all.count == 3)
    #expect(all.map(\.id) == [first.id, second.id, third.id])
}

@MainActor
@Test func linkRepository_allLinks_emptyTableReturnsEmpty() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    #expect(try repo.allLinks().isEmpty)
}

@MainActor
@Test func linkRepository_batchedOutgoing_matchesPerIDOutgoing() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    // A multi-task graph mixing blocking + non-blocking + cross-kind links,
    // plus a noise edge whose fromKind is NOT .task but shares a fromID.
    let t1 = UUID()
    let t2 = UUID()
    let t3 = UUID()  // has no outgoing .task links at all
    let shared = UUID()  // fromID reused with a non-task fromKind (must be filtered out)

    _ = try repo.create(from: (.task, t1), to: (.task, UUID()), linkKind: .blocks)
    _ = try repo.create(from: (.task, t1), to: (.note, UUID()), linkKind: .mentions)
    _ = try repo.create(from: (.task, t2), to: (.task, UUID()), linkKind: .blocks)
    _ = try repo.create(from: (.task, t2), to: (.meeting, UUID()), linkKind: .source)
    _ = try repo.create(from: (.note, shared), to: (.task, UUID()), linkKind: .mentions)
    _ = try repo.create(from: (.task, shared), to: (.project, UUID()), linkKind: .child)

    let ids = [t1, t2, t3, shared]
    let batched = try repo.outgoing(fromKind: .task, fromIDs: ids)

    for id in ids {
        let perID = try repo.outgoing(from: (.task, id))
        let grouped = batched[id] ?? []
        #expect(grouped.map(\.id) == perID.map(\.id), "mismatch for id \(id)")
    }
}

@MainActor
@Test func linkRepository_batchedBacklinks_matchesPerIDBacklinks() throws {
    let context = try makeContext()
    let repo = LinkRepository(context: context)

    let t1 = UUID()
    let t2 = UUID()
    let t3 = UUID()  // no backlinks
    let shared = UUID()  // toID reused with a non-task toKind (must be filtered out)

    _ = try repo.create(from: (.note, UUID()), to: (.task, t1), linkKind: .mentions)
    _ = try repo.create(from: (.meeting, UUID()), to: (.task, t1), linkKind: .source)
    _ = try repo.create(from: (.task, UUID()), to: (.task, t2), linkKind: .blocks)
    _ = try repo.create(from: (.note, UUID()), to: (.note, shared), linkKind: .mentions)
    _ = try repo.create(from: (.task, UUID()), to: (.task, shared), linkKind: .blocks)

    let ids = [t1, t2, t3, shared]
    let batched = try repo.backlinks(toKind: .task, toIDs: ids)

    for id in ids {
        let perID = try repo.backlinks(to: (.task, id))
        let grouped = batched[id] ?? []
        #expect(grouped.map(\.id) == perID.map(\.id), "mismatch for id \(id)")
    }
}

@MainActor
@Test func linkRepository_outgoing_preservesCreatedAtReverseOrder() throws {
    // Characterization: kind filter pushed into the predicate must not perturb
    // the createdAt-reverse sort. Insert several edges from one source.
    let context = try makeContext()
    let repo = LinkRepository(context: context)
    let source = UUID()
    let a = try repo.create(from: (.task, source), to: (.note, UUID()), linkKind: .mentions)
    let b = try repo.create(from: (.task, source), to: (.meeting, UUID()), linkKind: .source)
    let c = try repo.create(from: (.task, source), to: (.task, UUID()), linkKind: .blocks)
    // Distinct createdAt to make ordering deterministic (reverse = newest first).
    a.createdAt = Date(timeIntervalSince1970: 100)
    b.createdAt = Date(timeIntervalSince1970: 200)
    c.createdAt = Date(timeIntervalSince1970: 300)
    try context.save()

    let outgoing = try repo.outgoing(from: (.task, source))
    #expect(outgoing.map(\.id) == [c.id, b.id, a.id])

    let batched = try repo.outgoing(fromKind: .task, fromIDs: [source])
    #expect(batched[source]?.map(\.id) == [c.id, b.id, a.id])
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Link.self, DebugItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}
