import CoreSpotlight
import Foundation
import NexusCore
import Testing

@testable import NexusSearch

private actor RecordingIndex: SpotlightIndex {
    var indexed: [String] = []
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        indexed.append(contentsOf: items.compactMap(\.uniqueIdentifier))
    }
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {}
}

@Test func searchSubsystem_makeForTesting_givesSearchIndex() async {
    let subsystem = SearchSubsystem.makeForTesting()
    let count = await subsystem.searchIndex.documentCount
    #expect(count == 0)
}

@Test func searchSubsystem_observers_includeBothIndexAndSpotlight() async throws {
    let recording = RecordingIndex()
    let subsystem = SearchSubsystem.makeForTesting(spotlightIndex: recording)
    #expect(subsystem.observers.count == 2)
    let doc = IndexedDocument(kind: .debug, id: UUID(), text: "wired up", updatedAt: .now)
    for observer in subsystem.observers {
        await observer.didUpsert(doc)
    }
    let count = await subsystem.searchIndex.documentCount
    #expect(count == 1)
    let indexed = await recording.indexed
    #expect(indexed.count == 1)
}
