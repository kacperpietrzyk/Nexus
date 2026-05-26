import CoreSpotlight
import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSearch

/// Recording double used to capture donations + deletions issued by `SpotlightIndexer`.
private actor RecordingIndex: SpotlightIndex {
    var indexed: [String] = []
    var deleted: [String] = []
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        indexed.append(contentsOf: items.compactMap(\.uniqueIdentifier))
    }
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        deleted.append(contentsOf: identifiers)
    }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

/// Polling helper. `LinkableRepository` fans out to observers via fire-and-forget
/// `Task { ... }`; Swift's scheduler does NOT guarantee FIFO ordering between an
/// awaited `Task.yield()` and a freshly-spawned task on the same actor, so the
/// "yield N times" pattern is racy. See the documented rationale in
/// `Packages/NexusCore/Tests/NexusCoreTests/LinkableRepositoryObserverTests.swift`.
/// Polling avoids the race deterministically.
private func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: @Sendable () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
@Test func endToEnd_insertingDebugItem_indexesAndDonatesSpotlight() async throws {
    let context = try makeContext()
    let recording = RecordingIndex()
    let subsystem = SearchSubsystem.makeForTesting(spotlightIndex: recording)
    let repo = LinkableRepository<DebugItem>(context: context, observers: subsystem.observers)

    let item = DebugItem(title: "end-to-end: review code")
    try repo.insert(item)

    // Wait for both fan-out detached tasks (SearchIndex + SpotlightIndexer) to drain.
    await waitUntil { await subsystem.searchIndex.documentCount == 1 }
    await waitUntil { await recording.indexed.count == 1 }

    let hits = await subsystem.searchIndex.search("review", kinds: nil, limit: 5)
    #expect(hits.count == 1)
    #expect(hits.first?.itemID == item.id)

    let donated = await recording.indexed
    #expect(donated.contains(SpotlightDomain.uniqueIdentifier(kind: .debug, id: item.id)))
}

@MainActor
@Test func endToEnd_softDelete_removesFromBothIndexAndSpotlight() async throws {
    let context = try makeContext()
    let recording = RecordingIndex()
    let subsystem = SearchSubsystem.makeForTesting(spotlightIndex: recording)
    let repo = LinkableRepository<DebugItem>(context: context, observers: subsystem.observers)

    let item = DebugItem(title: "ephemeral entry")
    try repo.insert(item)
    await waitUntil { await subsystem.searchIndex.documentCount == 1 }
    await waitUntil { await recording.indexed.count == 1 }

    try repo.softDelete(item)
    await waitUntil { await subsystem.searchIndex.documentCount == 0 }
    await waitUntil { await recording.deleted.count == 1 }

    let hits = await subsystem.searchIndex.search("ephemeral", kinds: nil, limit: 5)
    #expect(hits.isEmpty)

    let deleted = await recording.deleted
    #expect(deleted.contains(SpotlightDomain.uniqueIdentifier(kind: .debug, id: item.id)))
}

@MainActor
@Test func endToEnd_rebuildAfterRestart_recoversIndex() async throws {
    let context = try makeContext()
    context.insert(DebugItem(title: "persistent alpha"))
    context.insert(DebugItem(title: "persistent beta"))
    try context.save()

    // Simulate an "app restart": fresh subsystem, no events were observed during inserts.
    let subsystem = SearchSubsystem.makeForTesting()
    let preCount = await subsystem.searchIndex.documentCount
    #expect(preCount == 0)

    try await subsystem.searchIndex.rebuild(from: context, types: DebugItem.self)
    let count = await subsystem.searchIndex.documentCount
    #expect(count == 2)

    let hits = await subsystem.searchIndex.search("beta", kinds: nil, limit: 5)
    #expect(hits.count == 1)
}
