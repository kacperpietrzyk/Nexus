import Foundation
import Testing

@testable import NexusCore

@Test func debugItem_conformsToSearchable() {
    let item: any Searchable = DebugItem(title: "hello")
    #expect(item.searchableText == "hello")
}

@Test func indexedDocument_fromDebugItem_extractsTitle() {
    let item = DebugItem(title: "Polish: książka")
    let doc = IndexedDocument(item)
    #expect(doc.kind == .debug)
    #expect(doc.id == item.id)
    #expect(doc.text == "Polish: książka")
}
