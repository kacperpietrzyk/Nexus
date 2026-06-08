import NexusCore
import Testing

@testable import PeopleFeature

@Suite("PeopleListFiltering")
struct PeopleListFilteringTests {
    @Test("Empty query returns the input unchanged")
    func emptyQueryPassthrough() {
        let people = [Person(displayName: "Alice"), Person(displayName: "Bob")]
        #expect(PeopleListFiltering.filter(people, query: "  ").count == 2)
    }

    @Test("Query matches display name case/diacritic-insensitively")
    func matchesDisplayNameFolded() {
        let people = [Person(displayName: "Renée"), Person(displayName: "Bob")]
        let hits = PeopleListFiltering.filter(people, query: "renee")
        #expect(hits.map(\.displayName) == ["Renée"])
    }

    @Test("Query matches aliases and company")
    func matchesAliasAndCompany() {
        let people = [
            Person(displayName: "Alice", aliases: ["Ali"]),
            Person(displayName: "Bob", company: "Acme Corp"),
        ]
        #expect(PeopleListFiltering.filter(people, query: "ali").map(\.displayName) == ["Alice"])
        #expect(PeopleListFiltering.filter(people, query: "acme").map(\.displayName) == ["Bob"])
    }

    @Test("Merge candidates exclude the target itself and soft-deleted people")
    func mergeCandidatesExcludeSelfAndDeleted() {
        let target = Person(displayName: "Alice")
        let deleted = Person(displayName: "Alice")
        deleted.deletedAt = .now
        let other = Person(displayName: "Bob")
        let candidates = PeopleListFiltering.mergeCandidates(for: target, among: [target, deleted, other])
        #expect(candidates.map(\.id) == [other.id])
    }

    @Test("Name/alias matches rank before non-matches")
    func nameMatchesRankFirst() {
        let target = Person(displayName: "Alice", aliases: ["Ali"])
        let dupByName = Person(displayName: "alice")
        let dupByAlias = Person(displayName: "Zed", aliases: ["Ali"])
        let unrelated = Person(displayName: "Bob")
        let candidates = PeopleListFiltering.mergeCandidates(
            for: target,
            among: [unrelated, dupByAlias, dupByName, target]
        )
        // Both name/alias matches first (alphabetical within group), then unrelated.
        #expect(candidates.prefix(2).map(\.displayName).sorted() == ["Zed", "alice"])
        #expect(candidates.last?.displayName == "Bob")
    }
}
