import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
private func makeObserverContext() throws -> ModelContext {
    let schema = Schema([TaskItem.self, Note.self, Label.self, Person.self, Link.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

private actor CapturingObserver: LinkableObserver {
    var upserts: [IndexedDocument] = []
    var deletes: [(ItemKind, UUID)] = []
    func didUpsert(_ doc: IndexedDocument) async { upserts.append(doc) }
    func didSoftDelete(kind: ItemKind, id: UUID) async { deletes.append((kind, id)) }
}

/// Fan-out runs in a fire-and-forget `Task { await ... }`, so a synchronous check
/// right after the mutation races. Poll with NO wall-clock ceiling (mirrors
/// `LinkableRepositoryObserverTests.waitUntil`): on a low-core CI runner the fan-out
/// task can be starved past any fixed timeout, yet it is always eventually delivered.
/// A `.timeLimit` trait on each test guards against a genuine never-fires regression.
private func waitUntil(_ condition: @Sendable () async -> Bool) async {
    while !(await condition()) {
        if Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

// MARK: - NoteRepository

@MainActor
@Test(.timeLimit(.minutes(1))) func noteRepository_create_fansOutUpsert() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = NoteRepository(context: context, observers: [observer])
    let note = try repo.create(
        title: "ignored",
        blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "snorkulent")]))]
    )
    await waitUntil { await observer.upserts.count == 1 }
    let upserts = await observer.upserts
    #expect(upserts.count == 1)
    #expect(upserts.first?.kind == .note)
    #expect(upserts.first?.id == note.id)
    #expect(upserts.first?.text.contains("snorkulent") == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func noteRepository_delete_fansOutSoftDelete() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = NoteRepository(context: context, observers: [observer])
    let note = try repo.create(blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "ephemeral")]))])
    try repo.delete(note)
    await waitUntil { await observer.deletes.count == 1 }
    let deletes = await observer.deletes
    #expect(deletes.count == 1)
    #expect(deletes.first?.0 == .note)
    #expect(deletes.first?.1 == note.id)
}

// MARK: - LabelRepository

@MainActor
@Test(.timeLimit(.minutes(1))) func labelRepository_create_fansOutUpsert() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = LabelRepository(context: context, observers: [observer])
    let label = try repo.create(name: "flummox")
    await waitUntil { await observer.upserts.count == 1 }
    let upserts = await observer.upserts
    #expect(upserts.count == 1)
    #expect(upserts.first?.kind == .label)
    #expect(upserts.first?.id == label.id)
    #expect(upserts.first?.text == "flummox")
}

@MainActor
@Test(.timeLimit(.minutes(1))) func labelRepository_softDelete_fansOutSoftDelete() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = LabelRepository(context: context, observers: [observer])
    let label = try repo.create(name: "transient")
    try repo.softDelete(label)
    await waitUntil { await observer.deletes.count == 1 }
    let deletes = await observer.deletes
    #expect(deletes.count == 1)
    #expect(deletes.first?.0 == .label)
    #expect(deletes.first?.1 == label.id)
}

// MARK: - PersonRepository

@MainActor
@Test(.timeLimit(.minutes(1))) func personRepository_create_fansOutUpsert() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = PersonRepository(context: context, observers: [observer])
    let person = try repo.create(displayName: "Quillsby Vandermeer")
    await waitUntil { await observer.upserts.count == 1 }
    let upserts = await observer.upserts
    #expect(upserts.count == 1)
    #expect(upserts.first?.kind == .person)
    #expect(upserts.first?.id == person.id)
    #expect(upserts.first?.text.contains("Quillsby") == true)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func personRepository_softDelete_fansOutSoftDelete() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = PersonRepository(context: context, observers: [observer])
    let person = try repo.create(displayName: "Doomed Person")
    try repo.softDelete(person)
    await waitUntil { await observer.deletes.count == 1 }
    let deletes = await observer.deletes
    #expect(deletes.count == 1)
    #expect(deletes.first?.0 == .person)
    #expect(deletes.first?.1 == person.id)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func personRepository_mergePeople_reUpsertsSurvivor_softDeletesDuplicate() async throws {
    let context = try makeObserverContext()
    let observer = CapturingObserver()
    let repo = PersonRepository(context: context, observers: [observer])
    let into = try repo.create(displayName: "Primary")
    let from = try repo.create(displayName: "Duplicate")
    let intoID = into.id
    let fromID = from.id
    // Two creates already fired two upserts; wait for them before the merge.
    await waitUntil { await observer.upserts.count == 2 }

    try repo.mergePeople(into: into, from: from)

    await waitUntil {
        let dels = await observer.deletes
        let ups = await observer.upserts
        return dels.contains { $0.1 == fromID }
            && ups.contains { $0.id == intoID && $0.text.contains("Duplicate") }
    }
    let deletes = await observer.deletes
    let upserts = await observer.upserts
    // Survivor re-indexed (now carries the merged alias), duplicate evicted.
    #expect(deletes.contains { $0.0 == .person && $0.1 == fromID })
    #expect(upserts.contains { $0.id == intoID && $0.text.contains("Duplicate") })
}
