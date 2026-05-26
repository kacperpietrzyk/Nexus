/// Pure utility for set-style merge of `[Hashable]` fields (e.g. `tags`, action item lists).
/// Used during conflict resolution to combine local and remote versions without losing entries.
/// Phase 0b ships the utility; wiring into the SwiftData merge path lands when real models
/// surface in Phase 1 (Tasks Module).
///
/// Local elements appear before remote elements; when both sides contain the same value
/// the local occurrence is retained and its position takes precedence (local-wins on ties).
public enum SetMerge {
    public static func union<Element: Hashable>(local: [Element], remote: [Element]) -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        for value in local + remote where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
