import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Container registering every type the apps pass to `SearchIndex.rebuild` so the
/// generic fetch over `Searchable` matches the concrete schema keypaths.
@MainActor
private func makeEntityContext() throws -> ModelContext {
    let schema = Schema([TaskItem.self, Note.self, Label.self, Person.self, Link.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

/// Regression guard for the gap this work closes: `Note`, `Label`, and `Person`
/// conform to `Searchable` but were absent from both app rebuild call sites, so
/// global search returned nothing for them after launch. Mirrors the app call
/// `index.rebuild(from:types: TaskItem.self, Note.self, Label.self, Person.self)`.
@MainActor
@Test func searchIndex_rebuild_indexesNoteLabelPerson() async throws {
    let context = try makeEntityContext()

    // Note's `searchableText` is the `plainText` cache (derived from blocks by the
    // reconciler), NOT the title — so build it through the repository.
    let notes = NoteRepository(context: context)
    try notes.create(
        title: "ignored title",
        blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "zorblify")]))]
    )

    let labels = LabelRepository(context: context)
    try labels.create(name: "quibbleton")

    let people = PersonRepository(context: context)
    try people.create(displayName: "Wexford Plimscott")

    let index = SearchIndex()
    try await index.rebuild(
        from: context,
        types: TaskItem.self, Note.self, Label.self, Person.self
    )

    let noteHits = await index.search("zorblify", kinds: nil, limit: 10)
    let labelHits = await index.search("quibbleton", kinds: nil, limit: 10)
    let personHits = await index.search("plimscott", kinds: nil, limit: 10)

    #expect(noteHits.contains { $0.itemKind == .note })
    #expect(labelHits.contains { $0.itemKind == .label })
    #expect(personHits.contains { $0.itemKind == .person })
}
