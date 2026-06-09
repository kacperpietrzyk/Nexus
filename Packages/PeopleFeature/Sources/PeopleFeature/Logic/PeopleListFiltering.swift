import Foundation
import NexusCore

/// The People list split into a primary alphabetical section model plus a
/// hidden-by-default "From meetings" reveal bucket (spec §6). `sections` is the
/// main, alphabetically-headed list; `fromMeetings` holds the numbered
/// auto-created placeholder rows ("Participant 3", "Speaker 1") that pollute the
/// surface and are suppressed until the user opts to reveal them.
public struct PeopleListModel: Equatable {
    public var sections: [PeopleListSection]
    public var fromMeetings: [Person]

    public init(sections: [PeopleListSection] = [], fromMeetings: [Person] = []) {
        self.sections = sections
        self.fromMeetings = fromMeetings
    }

    /// Flattened people in the main list (across all sections), order preserved.
    public var mainPeople: [Person] { sections.flatMap(\.people) }
}

/// One alphabetical bucket of the People list: a single uppercase first-letter
/// header ("A", "B", … or "#" for non-alpha/empty names) and its members.
public struct PeopleListSection: Equatable, Identifiable {
    public var title: String
    public var people: [Person]

    public var id: String { title }

    public init(title: String, people: [Person]) {
        self.title = title
        self.people = people
    }
}

/// Pure helpers for the People list + merge picker (spec §6). Kept free of SwiftUI
/// so search/merge-candidate ordering is unit-testable.
public enum PeopleListFiltering {
    /// Prefix every meeting-auto-created `Person` carries on its
    /// `externalSourceID` (mirrors `MeetingPeopleLinker`). Used only to scope the
    /// numbered-placeholder suppression to meeting-sourced rows.
    static let meetingParticipantPrefix = "meeting-participant:"

    /// Matches the junk auto-generated names — "Participant 3", "Speaker_1",
    /// "speaker 12" — case-insensitively, with an optional space/underscore before
    /// the trailing number. A real name ("Maya Chen", "Participant Ventures") never
    /// matches because the whole string must be the keyword + digits.
    static func isNumberedPlaceholderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: "^(participant|speaker)[ _]?\\d+$",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Whether `person` is a numbered placeholder that should be hidden from the
    /// main list by default. Scoped to meeting-sourced rows (so a manually-typed
    /// "Speaker 1" is left alone), but tolerant of a missing prefix when the name
    /// itself is unambiguously the junk pattern.
    public static func isHiddenPlaceholder(_ person: Person) -> Bool {
        guard isNumberedPlaceholderName(person.displayName) else { return false }
        guard let source = person.externalSourceID, !source.isEmpty else {
            // No source ⇒ likely manual; only auto-created rows are junk.
            return false
        }
        return source.hasPrefix(meetingParticipantPrefix)
    }

    /// First-letter section title for `person`: uppercased leading alpha character,
    /// or "#" for empty/non-alphabetic names. Used to bucket the sorted list.
    static func sectionTitle(for person: Person) -> String {
        let trimmed = person.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    /// Builds the sectioned list model from a (display-name-sorted) `people` list,
    /// applying the search `query` first. Numbered meeting placeholders are pulled
    /// out into `fromMeetings` (hidden-by-default reveal bucket); everyone else is
    /// grouped into sticky alphabetical sections. Section + member order follow the
    /// input order (callers pre-sort by `displayName`), so headers come out
    /// alphabetical with "#" last.
    public static func sectionedModel(_ people: [Person], query: String) -> PeopleListModel {
        let filtered = filter(people, query: query)
        var main: [Person] = []
        var placeholders: [Person] = []
        for person in filtered {
            if isHiddenPlaceholder(person) {
                placeholders.append(person)
            } else {
                main.append(person)
            }
        }

        var order: [String] = []
        var buckets: [String: [Person]] = [:]
        for person in main {
            let title = sectionTitle(for: person)
            if buckets[title] == nil {
                buckets[title] = []
                order.append(title)
            }
            buckets[title]?.append(person)
        }
        // Keep first-seen order but float "#" to the end (it sorts before letters).
        let sortedTitles = order.sorted { lhs, rhs in
            if lhs == "#" { return false }
            if rhs == "#" { return true }
            return lhs < rhs
        }
        let sections = sortedTitles.map { PeopleListSection(title: $0, people: buckets[$0] ?? []) }
        return PeopleListModel(sections: sections, fromMeetings: placeholders)
    }

    /// Case/diacritic-insensitive fold mirroring `PersonRepository.fold` so list
    /// search matches the repository's dedup soft-match semantics.
    static func fold(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filters `people` by a free-text query against display name, aliases, and
    /// company (the `Searchable.searchableText` surface, spec §9). An empty query
    /// returns the input unchanged. Order is preserved (callers pre-sort).
    public static func filter(_ people: [Person], query: String) -> [Person] {
        let needle = fold(query)
        guard !needle.isEmpty else { return people }
        return people.filter { person in
            let haystack = ([person.displayName] + person.aliases + [person.company].compactMap { $0 })
                .map(fold)
            return haystack.contains { $0.contains(needle) }
        }
    }

    /// Candidate duplicates to merge `target` INTO, excluding `target` itself and
    /// any soft-deleted person. Ranked: exact name/alias matches (most likely the
    /// same real person) first, then the rest, each group alphabetical. This drives
    /// the merge picker's "pick the duplicate" list (spec §4.3 / §6).
    public static func mergeCandidates(for target: Person, among people: [Person]) -> [Person] {
        let targetNames = Set(([target.displayName] + target.aliases).map(fold).filter { !$0.isEmpty })
        let others = people.filter { $0.id != target.id && $0.deletedAt == nil }

        func isNameMatch(_ person: Person) -> Bool {
            let names = ([person.displayName] + person.aliases).map(fold)
            return names.contains { targetNames.contains($0) }
        }

        let matches = others.filter(isNameMatch)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let rest = others.filter { !isNameMatch($0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return matches + rest
    }
}
