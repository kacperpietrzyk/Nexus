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

    // MARK: - Numbered-placeholder suppression (task #8)

    private static func meetingPerson(_ name: String) -> Person {
        Person(displayName: name, externalSourceID: "meeting-participant:\(name)")
    }

    @Test("Numbered placeholder name regex matches junk, spares real names")
    func placeholderRegex() {
        #expect(PeopleListFiltering.isNumberedPlaceholderName("Participant 3"))
        #expect(PeopleListFiltering.isNumberedPlaceholderName("participant3"))
        #expect(PeopleListFiltering.isNumberedPlaceholderName("Speaker_1"))
        #expect(PeopleListFiltering.isNumberedPlaceholderName("SPEAKER 12"))
        // Real names that merely contain the keyword are NOT junk.
        #expect(!PeopleListFiltering.isNumberedPlaceholderName("Participant Ventures"))
        #expect(!PeopleListFiltering.isNumberedPlaceholderName("Maya Chen"))
        #expect(!PeopleListFiltering.isNumberedPlaceholderName("Speaker"))
        #expect(!PeopleListFiltering.isNumberedPlaceholderName(""))
    }

    @Test("isHiddenPlaceholder only fires for meeting-sourced numbered junk")
    func hiddenPlaceholderScope() {
        // Meeting-sourced + numbered ⇒ hidden.
        #expect(PeopleListFiltering.isHiddenPlaceholder(Self.meetingPerson("Participant 2")))
        // Numbered name but NO source (manual) ⇒ kept.
        #expect(!PeopleListFiltering.isHiddenPlaceholder(Person(displayName: "Participant 2")))
        // Meeting-sourced but a real name ⇒ kept in main list.
        #expect(!PeopleListFiltering.isHiddenPlaceholder(Self.meetingPerson("Maya Chen")))
    }

    @Test("Sectioned model hides numbered placeholders, reveals them in fromMeetings")
    func sectionedModelPartitions() {
        let people = [
            Person(displayName: "Alice"),
            Self.meetingPerson("Bob Realname"),
            Self.meetingPerson("Participant 1"),
            Self.meetingPerson("Speaker 4"),
        ]
        let model = PeopleListFiltering.sectionedModel(people, query: "")

        let mainNames = model.mainPeople.map(\.displayName)
        #expect(mainNames.contains("Alice"))
        #expect(mainNames.contains("Bob Realname"))
        #expect(!mainNames.contains("Participant 1"))
        #expect(!mainNames.contains("Speaker 4"))

        let revealed = model.fromMeetings.map(\.displayName).sorted()
        #expect(revealed == ["Participant 1", "Speaker 4"])
    }

    @Test("Sectioned model groups by uppercase first letter with # bucket last")
    func sectionedModelGrouping() {
        let people = [
            Person(displayName: "8-bit Inc"),  // non-alpha → "#"
            Person(displayName: "alice"),
            Person(displayName: "Amir"),
            Person(displayName: "Bob"),
        ]
        let model = PeopleListFiltering.sectionedModel(people, query: "")

        #expect(model.sections.map(\.title) == ["A", "B", "#"])
        #expect(model.sections.first(where: { $0.title == "A" })?.people.map(\.displayName) == ["alice", "Amir"])
        #expect(model.sections.last?.title == "#")
        #expect(model.sections.last?.people.map(\.displayName) == ["8-bit Inc"])
    }

    @Test("Search applies before sectioning and placeholder split")
    func sectionedModelHonorsQuery() {
        let people = [
            Person(displayName: "Alice"),
            Person(displayName: "Bob"),
            Self.meetingPerson("Participant 1"),
        ]
        let model = PeopleListFiltering.sectionedModel(people, query: "ali")
        #expect(model.mainPeople.map(\.displayName) == ["Alice"])
        #expect(model.fromMeetings.isEmpty)
    }
}
