import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

@MainActor
@Test func searchIndex_rebuild_indexesAllLiveItems() async throws {
    let context = try makeContext()
    context.insert(DebugItem(title: "alpha first"))
    context.insert(DebugItem(title: "beta second"))
    context.insert(DebugItem(title: "gamma third"))
    try context.save()

    let index = SearchIndex()
    try await index.rebuild(from: context, types: DebugItem.self)
    let count = await index.documentCount
    #expect(count == 3)

    let hits = await index.search("beta", kinds: nil, limit: 10)
    #expect(hits.count == 1)
}

@MainActor
@Test func searchIndex_rebuild_skipsTombstones() async throws {
    let context = try makeContext()
    let live = DebugItem(title: "live one")
    let dead = DebugItem(title: "dead one")
    context.insert(live)
    context.insert(dead)
    dead.deletedAt = .now
    try context.save()

    let index = SearchIndex()
    try await index.rebuild(from: context, types: DebugItem.self)
    let count = await index.documentCount
    #expect(count == 1)

    let liveHits = await index.search("live", kinds: nil, limit: 10)
    let deadHits = await index.search("dead", kinds: nil, limit: 10)
    #expect(liveHits.count == 1)
    #expect(deadHits.isEmpty)
}

@MainActor
@Test func searchIndex_rebuild_clearsBeforePopulating() async throws {
    let context = try makeContext()
    context.insert(DebugItem(title: "stays"))
    try context.save()

    let index = SearchIndex()
    let stale = IndexedDocument(kind: .debug, id: UUID(), text: "stale ghost", updatedAt: .now)
    await index.upsert(stale)
    let preCount = await index.documentCount
    #expect(preCount == 1)

    try await index.rebuild(from: context, types: DebugItem.self)
    let count = await index.documentCount
    #expect(count == 1)
    let staleHits = await index.search("stale", kinds: nil, limit: 10)
    #expect(staleHits.isEmpty)
}
