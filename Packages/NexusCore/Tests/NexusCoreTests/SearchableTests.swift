import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Model final class TitleOnlySearchable: Searchable {
    var id: UUID = UUID()
    var kind: ItemKind = ItemKind.debug
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    init(title: String) { self.title = title }
}

@Model final class CustomSearchableItem: Searchable {
    var id: UUID = UUID()
    var kind: ItemKind = ItemKind.debug
    var title: String = ""
    var body: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?
    var searchableText: String { "\(title)\n\(body)" }
    init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

@Test func searchable_defaultSearchableText_returnsTitle() {
    let item = TitleOnlySearchable(title: "hello world")
    #expect((item as any Searchable).searchableText == "hello world")
}

@Test func searchable_canOverrideSearchableText() {
    let item = CustomSearchableItem(title: "T", body: "B")
    #expect(item.searchableText == "T\nB")
}
