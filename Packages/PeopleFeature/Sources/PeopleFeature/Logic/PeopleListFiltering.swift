import Foundation
import NexusCore

/// Pure helpers for the People list + merge picker (spec §6). Kept free of SwiftUI
/// so search/merge-candidate ordering is unit-testable.
public enum PeopleListFiltering {
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
