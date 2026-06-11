import Foundation
import NexusCore

/// The polymorphic graph edge, aliased so view files that also `import SwiftUI`
/// (where `Link` collides with `SwiftUI.Link`, and the module name is shadowed by
/// the `NexusCore` enum) can name it unambiguously for `@Query`. This file imports
/// only `NexusCore`, so `Link` resolves to the model here.
public typealias GraphLink = Link

/// Pure, view-independent helpers that turn a flat `[Note]` into the grouped,
/// metadata-bearing shape the Notes list renders (spec: Obsidian-like in-app
/// organization). Kept here (not in the view) so the grouping + tag editing logic
/// is unit-testable without a `ModelContext`, mirroring `BlockListOps` and
/// `LinkPickerFiltering`.
public enum NoteListGrouping {

    /// How the flat note list is sectioned. `role` is the always-available
    /// organization story while folders (a schema change) are deferred.
    public enum Mode: String, CaseIterable, Sendable {
        case role
        case tag
    }

    /// A resolved section: a stable key, a human title, and its notes (already in
    /// the caller's sort order — this never re-sorts).
    public struct Group: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let notes: [Note]

        public init(id: String, title: String, notes: [Note]) {
            self.id = id
            self.title = title
            self.notes = notes
        }

        public static func == (lhs: Group, rhs: Group) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.notes.map(\.id) == rhs.notes.map(\.id)
        }
    }

    /// Section the notes, preserving each note's incoming order inside a group.
    /// Group order is deterministic: by `role` it follows a fixed role order; by
    /// `tag` it is the untagged bucket last and tags alphabetically before it.
    public static func groups(for notes: [Note], mode: Mode) -> [Group] {
        switch mode {
        case .role: return roleGroups(notes)
        case .tag: return tagGroups(notes)
        }
    }

    // MARK: - Role

    private static func roleGroups(_ notes: [Note]) -> [Group] {
        // Fixed, stable role order so sections never reshuffle as notes change.
        let order: [NoteRole] = [.free, .projectPage, .dailyNote]
        return order.compactMap { role in
            let bucket = notes.filter { $0.role == role }
            guard !bucket.isEmpty else { return nil }
            return Group(id: role.rawValue, title: roleTitle(role), notes: bucket)
        }
    }

    public static func roleTitle(_ role: NoteRole) -> String {
        switch role {
        case .free: return "Notes"
        case .projectPage: return "Project Pages"
        case .dailyNote: return "Daily Notes"
        case .template: return "Templates"
        }
    }

    // MARK: - Tag

    /// Sentinel id for the "no tags" bucket. Not a valid tag (tags are trimmed
    /// non-empty), so it can never collide with a real group.
    public static let untaggedGroupID = "\u{0000}untagged"

    private static func tagGroups(_ notes: [Note]) -> [Group] {
        var byTag: [String: [Note]] = [:]
        var untagged: [Note] = []
        for note in notes {
            let tags = normalizedTags(note.tags)
            if tags.isEmpty {
                untagged.append(note)
            } else {
                // A note appears under each of its tags (Obsidian behavior).
                for tag in tags { byTag[tag, default: []].append(note) }
            }
        }

        var groups = byTag.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { tag in Group(id: tag, title: "#\(tag)", notes: byTag[tag] ?? []) }

        if !untagged.isEmpty {
            groups.append(Group(id: untaggedGroupID, title: "No tags", notes: untagged))
        }
        return groups
    }

    // MARK: - Tags

    /// Normalize a stored tag list: trim whitespace and a leading `#`, drop empties,
    /// and de-duplicate case-insensitively while preserving first-seen order.
    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let trimmed = cleanTag(raw)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    /// Add a single tag to an existing list, normalizing the result. A no-op (other
    /// than normalization) when the tag is blank or already present.
    public static func addTag(_ raw: String, to tags: [String]) -> [String] {
        normalizedTags(tags + [raw])
    }

    /// Remove a tag (case-insensitive) from the list, normalizing the result.
    public static func removeTag(_ raw: String, from tags: [String]) -> [String] {
        let target = cleanTag(raw).lowercased()
        return normalizedTags(tags).filter { $0.lowercased() != target }
    }

    /// Strip surrounding whitespace and a single leading `#` (users type either).
    private static func cleanTag(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Backlink counts

    /// Fold the whole `Link` table into a `[noteID: incoming-link count]` map in a
    /// single pass, so the list never runs a per-row `FetchDescriptor<Link>` on the
    /// main actor (the documented hot-path rule). Only edges that *point at a note*
    /// (`toKind == .note`) count; `toKind` is an enum stored field so we filter in
    /// memory exactly as `NoteRepository.backlinks(to:)` does.
    public static func backlinkCounts(from links: [GraphLink]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for link in links where link.toKind == .note {
            counts[link.toID, default: 0] += 1
        }
        return counts
    }
}
