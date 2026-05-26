import CoreSpotlight
import Foundation
import NexusCore
import Testing

@testable import NexusSearch

private actor RecordingIndex: SpotlightIndex {
    var indexed: [CSSearchableItem] = []
    var deletedIdentifiers: [String] = []
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        indexed.append(contentsOf: items)
    }
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        deletedIdentifiers.append(contentsOf: identifiers)
    }
}

@Test func spotlightIndexer_didUpsert_indexesSingleItem() async throws {
    let backing = RecordingIndex()
    let indexer = SpotlightIndexer(index: backing)
    let id = UUID()
    let doc = IndexedDocument(kind: .debug, id: id, text: "indexed by spotlight", updatedAt: .now)
    await indexer.didUpsert(doc)

    let indexed = await backing.indexed
    #expect(indexed.count == 1)
    #expect(indexed.first?.uniqueIdentifier == SpotlightDomain.uniqueIdentifier(kind: .debug, id: id))
}

@Test func spotlightIndexer_didSoftDelete_deletesByIdentifier() async throws {
    let backing = RecordingIndex()
    let indexer = SpotlightIndexer(index: backing)
    let id = UUID()
    await indexer.didSoftDelete(kind: .debug, id: id)

    let deletes = await backing.deletedIdentifiers
    #expect(deletes == [SpotlightDomain.uniqueIdentifier(kind: .debug, id: id)])
}

@Test func spotlightIndexer_swallowsBackingErrors() async throws {
    actor FailingIndex: SpotlightIndex {
        struct Boom: Error {}
        func indexSearchableItems(_ items: [CSSearchableItem]) async throws { throw Boom() }
        func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws { throw Boom() }
    }
    let indexer = SpotlightIndexer(index: FailingIndex())
    let doc = IndexedDocument(kind: .debug, id: UUID(), text: "x", updatedAt: .now)
    await indexer.didUpsert(doc)
    await indexer.didSoftDelete(kind: .debug, id: UUID())
    #expect(true)
}
