import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Local helper because `DebugItem` does not yet conform to `Searchable`
/// (Task 6 will add that conformance natively). Mirrors the file-scope helper
/// pattern from `SearchableTests.swift` to avoid cross-test-file coupling.
@Model final class ObserverTestItem: Searchable {
    var id: UUID = UUID()
    var kind: ItemKind = ItemKind.debug
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    init(title: String) { self.title = title }
}

@Test func indexedDocument_holdsSendablePayload() {
    let id = UUID()
    let doc = IndexedDocument(kind: .debug, id: id, text: "hello", updatedAt: .distantPast)
    #expect(doc.kind == .debug)
    #expect(doc.id == id)
    #expect(doc.text == "hello")
    #expect(doc.updatedAt == .distantPast)
}

@Test func indexedDocument_init_fromSearchable_extractsCorrectly() {
    let item = ObserverTestItem(title: "title text")
    let doc = IndexedDocument(item)
    #expect(doc.kind == .debug)
    #expect(doc.id == item.id)
    #expect(doc.text == "title text")  // Searchable default returns title
    #expect(doc.updatedAt == item.updatedAt)
}

@Test func observer_canBeStored_asExistential() async {
    actor RecordingObserver: LinkableObserver {
        var upserts: [IndexedDocument] = []
        var deletes: [(ItemKind, UUID)] = []
        func didUpsert(_ doc: IndexedDocument) async { upserts.append(doc) }
        func didSoftDelete(kind: ItemKind, id: UUID) async { deletes.append((kind, id)) }
    }

    let observer = RecordingObserver()
    let observers: [any LinkableObserver] = [observer]
    let id = UUID()
    let doc = IndexedDocument(kind: .debug, id: id, text: "x", updatedAt: .now)
    for o in observers { await o.didUpsert(doc) }
    for o in observers { await o.didSoftDelete(kind: .debug, id: id) }

    let upserts = await observer.upserts
    let deletes = await observer.deletes
    #expect(upserts.count == 1)
    #expect(upserts.first?.id == id)
    #expect(deletes.count == 1)
    #expect(deletes.first?.0 == .debug)
    #expect(deletes.first?.1 == id)
}
