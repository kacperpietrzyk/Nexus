import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("LinkPickerFiltering")
struct LinkPickerFilteringTests {

    private func candidate(_ title: String) -> LinkCandidate {
        LinkCandidate(id: UUID(), kind: .note, title: title)
    }

    @Test("empty query returns all, shortest-title first")
    func emptyQuery() {
        let result = LinkPickerFiltering.filter(
            [candidate("Roadmap"), candidate("Q3"), candidate("Notes")],
            query: ""
        )
        #expect(result.map(\.title) == ["Q3", "Notes", "Roadmap"])
    }

    @Test("substring filter is case-insensitive")
    func caseInsensitive() {
        let result = LinkPickerFiltering.filter(
            [candidate("Roadmap"), candidate("Backlog")],
            query: "ROAD"
        )
        #expect(result.map(\.title) == ["Roadmap"])
    }

    @Test("a prefix match ranks above a mid-string match")
    func prefixRanksFirst() {
        let result = LinkPickerFiltering.filter(
            [candidate("My plan"), candidate("Plan A")],
            query: "plan"
        )
        #expect(result.map(\.title) == ["Plan A", "My plan"])
    }

    @Test("diacritics fold so 'projekt' matches 'Projekt'")
    func diacriticInsensitive() {
        let result = LinkPickerFiltering.filter([candidate("Café notes")], query: "cafe")
        #expect(result.map(\.title) == ["Café notes"])
    }

    @Test("limit caps the result count")
    func limit() {
        let many = (0..<50).map { candidate("Note \($0)") }
        let result = LinkPickerFiltering.filter(many, query: "Note", limit: 5)
        #expect(result.count == 5)
    }

    @Test("no match yields an empty result")
    func noMatch() {
        let result = LinkPickerFiltering.filter([candidate("Roadmap")], query: "zzz")
        #expect(result.isEmpty)
    }
}
