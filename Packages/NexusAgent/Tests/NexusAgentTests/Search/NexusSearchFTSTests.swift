import Foundation
import NexusCore
import Testing

@testable import NexusAgent

@Test func nexusSearchFTSReturnsHits() async throws {
    let searchIndex = SearchIndex()
    let id = UUID()
    await searchIndex.upsert(IndexedDocument(kind: .task, id: id, text: "buy oat milk", updatedAt: .now))
    let fts = NexusSearchFTS(index: searchIndex)

    let hits = try await fts.search(query: "oat", limit: 10)

    #expect(hits == [id])
}

@Test func nexusSearchFTSTrimsWhitespaceQuery() async throws {
    let searchIndex = SearchIndex()
    let id = UUID()
    await searchIndex.upsert(IndexedDocument(kind: .task, id: id, text: "buy oat milk", updatedAt: .now))
    let fts = NexusSearchFTS(index: searchIndex)

    let hits = try await fts.search(query: " \n oat \t ", limit: 10)

    #expect(hits == [id])
}

@Test func nexusSearchFTSReturnsEmptyForBlankQueryOrNonPositiveLimit() async throws {
    let searchIndex = SearchIndex()
    let id = UUID()
    await searchIndex.upsert(IndexedDocument(kind: .task, id: id, text: "buy oat milk", updatedAt: .now))
    let fts = NexusSearchFTS(index: searchIndex)

    let blankHits = try await fts.search(query: " \n\t ", limit: 10)
    let zeroLimitHits = try await fts.search(query: "oat", limit: 0)
    let negativeLimitHits = try await fts.search(query: "oat", limit: -1)

    #expect(blankHits.isEmpty)
    #expect(zeroLimitHits.isEmpty)
    #expect(negativeLimitHits.isEmpty)
}
