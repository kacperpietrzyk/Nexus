import Foundation
import NexusCore

/// A pickable link/embed target surfaced by the wikilink + embed autocomplete.
/// The editor stores the chosen target by `id` (rename-safe, spec §9), never by
/// title.
public struct LinkCandidate: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String

    public init(id: UUID, kind: ItemKind, title: String) {
        self.id = id
        self.kind = kind
        self.title = title
    }
}

/// Pure autocomplete ranking for the wikilink/embed picker. Filters candidates by
/// a case/diacritic-insensitive substring of the title, ranking a prefix match
/// above a mid-string match, then by title length, then alphabetically — a stable
/// order the picker view binds to.
public enum LinkPickerFiltering {

    public static func filter(
        _ candidates: [LinkCandidate],
        query: String,
        limit: Int = 20
    ) -> [LinkCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(
                candidates.sorted { lhs, rhs in
                    titleSort(lhs, rhs)
                }.prefix(limit)
            )
        }
        let needle = fold(trimmed)
        let scored =
            candidates
            .compactMap { candidate -> (LinkCandidate, Int)? in
                let hay = fold(candidate.title)
                guard let range = hay.range(of: needle) else { return nil }
                let rank = range.lowerBound == hay.startIndex ? 0 : 1
                return (candidate, rank)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return titleSort(lhs.0, rhs.0)
            }
            .map(\.0)
        return Array(scored.prefix(limit))
    }

    private static func titleSort(_ lhs: LinkCandidate, _ rhs: LinkCandidate) -> Bool {
        if lhs.title.count != rhs.title.count { return lhs.title.count < rhs.title.count }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
