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
private func makeContext() throws -> ModelContext {
    let schema = Schema([Link.self, DebugItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}
