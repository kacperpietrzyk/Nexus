import CoreSpotlight
import Foundation
import NexusCore
import Testing

@testable import NexusSearch

@Test func attrSet_titleIsFirstLineOfText() {
    let id = UUID()
    let doc = IndexedDocument(kind: .debug, id: id, text: "first line\nsecond line", updatedAt: .now)
    let attrs = SpotlightAttributeSetMapping.makeAttributeSet(for: doc)
    #expect(attrs.title == "first line")
}

@Test func attrSet_contentDescriptionIsFullText() {
    let doc = IndexedDocument(kind: .debug, id: UUID(), text: "ABC", updatedAt: .now)
    let attrs = SpotlightAttributeSetMapping.makeAttributeSet(for: doc)
    #expect(attrs.contentDescription == "ABC")
}

@Test func attrSet_emptyText_titleIsKindRawValue() {
    let doc = IndexedDocument(kind: .task, id: UUID(), text: "", updatedAt: .now)
    let attrs = SpotlightAttributeSetMapping.makeAttributeSet(for: doc)
    #expect(attrs.title == "task")
}

@Test func searchableItem_usesStableIdentifierAndSubdomain() {
    let id = UUID()
    let doc = IndexedDocument(kind: .debug, id: id, text: "anything", updatedAt: .now)
    let item = SpotlightAttributeSetMapping.makeSearchableItem(for: doc)
    #expect(item.uniqueIdentifier == SpotlightDomain.uniqueIdentifier(kind: .debug, id: id))
    #expect(item.domainIdentifier == SpotlightDomain.subdomain(for: .debug))
}
