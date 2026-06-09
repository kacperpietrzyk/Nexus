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

private actor RecordingObserver: LinkableObserver {
    var upserts: [IndexedDocument] = []
    var deletes: [(ItemKind, UUID)] = []
    func didUpsert(_ doc: IndexedDocument) async { upserts.append(doc) }
    func didSoftDelete(kind: ItemKind, id: UUID) async { deletes.append((kind, id)) }
}

/// Polls until `condition` holds. The repository fans out via a fire-and-forget
/// `Task { ... }` (inheriting `@MainActor` isolation), so a synchronous check right
/// after the mutation races. We poll with NO wall-clock ceiling: on a low-core CI
/// runner many parallel `@MainActor` tests each run a long, non-suspending prefix
/// (`ModelContainer` init + `save()`) that can starve the fan-out task for far longer
/// than any fixed timeout we could justify — yet it is always *eventually* delivered
/// (the unstructured `Task` is never cancelled and the observer actor only appends).
/// A `.timeLimit` trait on each test is the coarse safety net that turns a genuine
/// never-fires regression into a loud failure instead of an unbounded hang.
private func waitUntil(_ condition: @Sendable () async -> Bool) async {
    while !(await condition()) {
        if Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func repository_insert_fanOutToObserver_async() async throws {
    let context = try makeContext()
    let observer = RecordingObserver()
    let repo = LinkableRepository<DebugItem>(context: context, observers: [observer])
    let item = DebugItem(title: "indexed title")
    try repo.insert(item)
    await waitUntil { await observer.upserts.count == 1 }
    let upserts = await observer.upserts
    #expect(upserts.count == 1)
    #expect(upserts.first?.id == item.id)
    #expect(upserts.first?.text == "indexed title")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func repository_softDelete_fanOutToObserver() async throws {
    let context = try makeContext()
    let observer = RecordingObserver()
    let repo = LinkableRepository<DebugItem>(context: context, observers: [observer])
    let item = DebugItem(title: "to be deleted")
    try repo.insert(item)
    try repo.softDelete(item)
    await waitUntil { await observer.deletes.count == 1 }
    let deletes = await observer.deletes
    #expect(deletes.count == 1)
    #expect(deletes.first?.0 == .debug)
    #expect(deletes.first?.1 == item.id)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func repository_restore_emitsUpsert() async throws {
    let context = try makeContext()
    let observer = RecordingObserver()
    let repo = LinkableRepository<DebugItem>(context: context, observers: [observer])
    let item = DebugItem(title: "restored")
    try repo.insert(item)
    try repo.softDelete(item)
    try repo.restore(item)
    await waitUntil { await observer.upserts.count == 2 }
    let upserts = await observer.upserts
    #expect(upserts.count == 2)
    #expect(upserts.allSatisfy { $0.id == item.id })
}

@MainActor
@Test func repository_emptyObservers_stillWorks() throws {
    let context = try makeContext()
    let repo = LinkableRepository<DebugItem>(context: context)
    let item = DebugItem(title: "no observers")
    #expect(throws: Never.self) { try repo.insert(item) }
}

@MainActor
@Test(.timeLimit(.minutes(1))) func repository_multipleObservers_allReceiveEvents() async throws {
    let context = try makeContext()
    let a = RecordingObserver()
    let b = RecordingObserver()
    let repo = LinkableRepository<DebugItem>(context: context, observers: [a, b])
    try repo.insert(DebugItem(title: "fanout"))
    await waitUntil {
        let countA = await a.upserts.count
        let countB = await b.upserts.count
        return countA == 1 && countB == 1
    }
    let upsertsA = await a.upserts
    let upsertsB = await b.upserts
    #expect(upsertsA.count == 1)
    #expect(upsertsB.count == 1)
}
