import Foundation
import Testing

@testable import NexusCore

@Test func searchHit_holdsKindIDSnippetScore() {
    let id = UUID()
    let hit = SearchHit(itemKind: .debug, itemID: id, snippet: "snip", score: 1.5)
    #expect(hit.itemKind == .debug)
    #expect(hit.itemID == id)
    #expect(hit.snippet == "snip")
    #expect(hit.score == 1.5)
}

@Test func searchHit_isEquatable_byAllFields() {
    let id = UUID()
    let a = SearchHit(itemKind: .debug, itemID: id, snippet: "x", score: 1.0)
    let b = SearchHit(itemKind: .debug, itemID: id, snippet: "x", score: 1.0)
    let c = SearchHit(itemKind: .debug, itemID: id, snippet: "y", score: 1.0)
    #expect(a == b)
    #expect(a != c)
}

@Test func searchHit_isSendable() {
    actor Probe { func accept(_ hit: SearchHit) {} }
    _ = Probe()
}
