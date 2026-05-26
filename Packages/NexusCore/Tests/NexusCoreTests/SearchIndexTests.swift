import Foundation
import Testing

@testable import NexusCore

private func doc(_ kind: ItemKind, _ text: String, _ updatedAt: Date = .now) -> IndexedDocument {
    IndexedDocument(kind: kind, id: UUID(), text: text, updatedAt: updatedAt)
}

@Test func searchIndex_emptyIndex_returnsNoHits() async {
    let index = SearchIndex()
    let hits = await index.search("foo", kinds: nil, limit: 10)
    #expect(hits.isEmpty)
}

@Test func searchIndex_upsert_findsByExactToken() async {
    let index = SearchIndex()
    let d = doc(.debug, "hello world")
    await index.upsert(d)
    let hits = await index.search("hello", kinds: nil, limit: 10)
    #expect(hits.count == 1)
    #expect(hits.first?.itemID == d.id)
}

@Test func searchIndex_search_isCaseAndDiacriticInsensitive() async {
    let index = SearchIndex()
    let d = doc(.debug, "Książka jest świetna")
    await index.upsert(d)
    let h1 = await index.search("KSIAZKA", kinds: nil, limit: 10)
    let h2 = await index.search("ksiazka", kinds: nil, limit: 10)
    let h3 = await index.search("książka", kinds: nil, limit: 10)
    #expect(h1.first?.itemID == d.id)
    #expect(h2.first?.itemID == d.id)
    #expect(h3.first?.itemID == d.id)
}

@Test func searchIndex_kindsFilter_excludesOtherKinds() async {
    let index = SearchIndex()
    let debug = doc(.debug, "review the code")
    let task = doc(.task, "review the code")
    await index.upsert(debug)
    await index.upsert(task)
    let onlyTasks = await index.search("review", kinds: [.task], limit: 10)
    #expect(onlyTasks.count == 1)
    #expect(onlyTasks.first?.itemKind == .task)
    #expect(onlyTasks.first?.itemID == task.id)
}

@Test func searchIndex_limit_capsResultCount() async {
    let index = SearchIndex()
    for i in 0..<5 {
        await index.upsert(doc(.debug, "common token doc number \(i)"))
    }
    let hits = await index.search("common", kinds: nil, limit: 3)
    #expect(hits.count == 3)
}

@Test func searchIndex_remove_removesFromIndex() async {
    let index = SearchIndex()
    let d = doc(.debug, "transient text")
    await index.upsert(d)
    await index.remove(kind: d.kind, id: d.id)
    let hits = await index.search("transient", kinds: nil, limit: 10)
    #expect(hits.isEmpty)
}

@Test func searchIndex_upsert_replacesExistingDocument() async {
    let index = SearchIndex()
    let id = UUID()
    let v1 = IndexedDocument(kind: .debug, id: id, text: "old text", updatedAt: .distantPast)
    let v2 = IndexedDocument(kind: .debug, id: id, text: "new content", updatedAt: .now)
    await index.upsert(v1)
    await index.upsert(v2)
    let oldHits = await index.search("old", kinds: nil, limit: 10)
    let newHits = await index.search("new", kinds: nil, limit: 10)
    #expect(oldHits.isEmpty)
    #expect(newHits.count == 1)
    #expect(newHits.first?.itemID == id)
}

@Test func searchIndex_rareTermsRankAboveCommonTerms() async {
    let index = SearchIndex()
    var rareID: UUID = UUID()
    var commonID: UUID = UUID()
    for i in 0..<10 {
        let d = IndexedDocument(
            kind: .debug, id: UUID(),
            text: "common token \(i)", updatedAt: .now)
        if i == 9 {
            commonID = d.id
        }
        await index.upsert(d)
    }
    let rare = IndexedDocument(
        kind: .debug, id: UUID(),
        text: "common rare combination", updatedAt: .now)
    rareID = rare.id
    await index.upsert(rare)

    let hits = await index.search("common rare", kinds: nil, limit: 5)
    #expect(hits.first?.itemID == rareID)
    #expect(hits.contains { $0.itemID == commonID })
}

@Test func searchIndex_search_returnsSnippet() async {
    let index = SearchIndex()
    let d = doc(.debug, "lorem ipsum dolor target sit amet consectetur adipiscing")
    await index.upsert(d)
    let hits = await index.search("target", kinds: nil, limit: 1)
    #expect(hits.first?.snippet.contains("target") == true)
}

@Test func searchIndex_clear_emptiesIndex() async {
    let index = SearchIndex()
    await index.upsert(doc(.debug, "anything"))
    await index.clear()
    let count = await index.documentCount
    #expect(count == 0)
}

@Test func searchIndex_didSoftDelete_callsRemove() async {
    let index = SearchIndex()
    let d = doc(.debug, "soft delete me")
    await index.upsert(d)
    await index.didSoftDelete(kind: d.kind, id: d.id)
    let hits = await index.search("soft", kinds: nil, limit: 10)
    #expect(hits.isEmpty)
}

@Test func searchIndex_didUpsert_callsUpsert() async {
    let index = SearchIndex()
    let d = doc(.debug, "observer wired")
    await index.didUpsert(d)
    let hits = await index.search("wired", kinds: nil, limit: 10)
    #expect(hits.count == 1)
    #expect(hits.first?.itemID == d.id)
}
