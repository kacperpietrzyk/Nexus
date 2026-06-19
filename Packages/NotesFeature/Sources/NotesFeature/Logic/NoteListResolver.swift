import Foundation
import NexusCore

/// Which set of notes the right-pane list shows. Drives `NoteListResolver`.
public enum NoteContainer: Hashable, Sendable {
    case overview            // Pinned + Recent — the default entry slice
    case unfiled
    case journal
    case templates
    case project(UUID)
    case folder(String)      // a Library folder path; notes directly at this path
}

/// Pure mapping from a selected `NoteContainer` (+ the already-built tree) to the
/// ordered sections the right pane renders. The tree is the single source of
/// truth for the structural slices (unfiled/projects/library/journal/templates);
/// `.overview` is computed from `allNotes` so Pinned/Recent span everything.
public enum NoteListResolver {

    public struct Section: Identifiable, Equatable {
        public let id: String
        /// nil = render as a single ungrouped list with no header.
        public let title: String?
        public let notes: [Note]
        public init(id: String, title: String?, notes: [Note]) {
            self.id = id
            self.title = title
            self.notes = notes
        }
        public static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title
                && lhs.notes.map(\.id) == rhs.notes.map(\.id)
        }
    }

    public struct Result: Equatable {
        public let sections: [Section]
        public let truncated: Bool
    }

    public static func resolve(
        container: NoteContainer,
        tree: NoteTreeModel.Tree,
        allNotes: [Note],
        recentLimit: Int = 50
    ) -> Result {
        switch container {
        case .overview:
            return overview(allNotes: allNotes, recentLimit: recentLimit)
        case .unfiled:
            return single(byUpdatedDesc(tree.unfiled))
        case .journal:
            return single(byUpdatedDesc(tree.journal))
        case .templates:
            return single(byUpdatedDesc(tree.templates))
        case .project(let id):
            guard let section = tree.projects.first(where: { $0.id == id }) else {
                return Result(sections: [], truncated: false)
            }
            let notes = ([section.canonical].compactMap { $0 }) + section.notes
            return single(byUpdatedDesc(notes))
        case .folder(let path):
            let node = findFolder(path, in: tree.library)
            return single(byUpdatedDesc(node?.notes ?? []))
        }
    }

    // MARK: - Helpers

    private static func overview(allNotes: [Note], recentLimit: Int) -> Result {
        let live = allNotes.filter { $0.deletedAt == nil && $0.role != .template }
        let pinned = live.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
        let recentAll = live.filter { !$0.isPinned }
            .sorted { $0.updatedAt > $1.updatedAt }
        let recent = Array(recentAll.prefix(recentLimit))
        var sections: [Section] = []
        if !pinned.isEmpty {
            sections.append(Section(id: "pinned", title: "Pinned", notes: pinned))
        }
        sections.append(Section(id: "recent", title: "Recent", notes: recent))
        return Result(sections: sections, truncated: recentAll.count > recent.count)
    }

    private static func single(_ notes: [Note]) -> Result {
        Result(sections: [Section(id: "all", title: nil, notes: notes)], truncated: false)
    }

    private static func byUpdatedDesc(_ notes: [Note]) -> [Note] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func findFolder(
        _ path: String, in nodes: [NoteTreeModel.FolderNode]
    ) -> NoteTreeModel.FolderNode? {
        for node in nodes {
            if node.id == path { return node }
            if let hit = findFolder(path, in: node.children) { return hit }
        }
        return nil
    }
}
