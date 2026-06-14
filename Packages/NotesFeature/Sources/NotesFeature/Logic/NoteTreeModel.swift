import Foundation
import NexusCore

/// Pure, view-independent builder that folds the live note set + the Link graph +
/// the active projects into the sectioned, nested tree the Notes navigator renders
/// (spec §4–§5). Mirrors `NoteListGrouping`: no `ModelContext`, fully unit-testable.
public enum NoteTreeModel {

    /// Lightweight project descriptor (the view maps `@Query Project` → this, so
    /// this file stays free of SwiftData fetches).
    public struct ProjectRef: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let canonicalNoteRef: UUID?
        public init(id: UUID, title: String, canonicalNoteRef: UUID?) {
            self.id = id
            self.title = title
            self.canonicalNoteRef = canonicalNoteRef
        }
    }

    public struct ProjectSection: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let canonical: Note?
        public let notes: [Note]
        public static func == (lhs: ProjectSection, rhs: ProjectSection) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title
                && lhs.canonical?.id == rhs.canonical?.id
                && lhs.notes.map(\.id) == rhs.notes.map(\.id)
        }
    }

    /// A folder in the Library tree. `id` is the full normalized path; `name` is
    /// the last path component.
    public struct FolderNode: Identifiable, Equatable {
        public let id: String
        public let name: String
        public var children: [FolderNode]
        public var notes: [Note]
        public static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name
                && lhs.children == rhs.children
                && lhs.notes.map(\.id) == rhs.notes.map(\.id)
        }
    }

    public struct Tree: Equatable {
        public let unfiled: [Note]
        public let projects: [ProjectSection]
        public let library: [FolderNode]
        public let journal: [Note]
        public let templates: [Note]
    }

    public static func build(notes: [Note], links: [GraphLink], projects: [ProjectRef]) -> Tree {
        let live = notes.filter { $0.deletedAt == nil }
        let byID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })

        // Build note-id → set of project-ids it is linked to (either edge direction).
        var projectIDsByNote: [UUID: Set<UUID>] = [:]
        let projectIDSet = Set(projects.map(\.id))
        for link in links {
            if link.fromKind == .note, link.toKind == .project, projectIDSet.contains(link.toID) {
                projectIDsByNote[link.fromID, default: []].insert(link.toID)
            } else if link.fromKind == .project, link.toKind == .note, projectIDSet.contains(link.fromID) {
                projectIDsByNote[link.toID, default: []].insert(link.fromID)
            }
        }
        let projectLinkedNoteIDs = Set(projectIDsByNote.keys)

        let projectSections = projects.map { ref -> ProjectSection in
            let canonical = ref.canonicalNoteRef.flatMap { byID[$0] }
            let linked = live.filter {
                $0.id != canonical?.id && (projectIDsByNote[$0.id]?.contains(ref.id) ?? false)
            }
            return ProjectSection(id: ref.id, title: ref.title, canonical: canonical, notes: linked)
        }

        let free = live.filter { $0.role == .free }
        let unfiled = free.filter { $0.folderPath == nil && !projectLinkedNoteIDs.contains($0.id) }
        let library = buildFolderTree(free.filter { $0.folderPath != nil })
        let journal = live.filter { $0.role == .dailyNote }
        let templates = live.filter { $0.role == .template }

        return Tree(
            unfiled: unfiled,
            projects: projectSections,
            library: library,
            journal: journal,
            templates: templates
        )
    }

    /// Build the nested folder tree from notes that all have a non-nil
    /// `folderPath`. Intermediate components become empty folder nodes. Children
    /// and notes are emitted in case-insensitive path order for stability.
    private static func buildFolderTree(_ notes: [Note]) -> [FolderNode] {
        final class MutableNode {
            var children: [String: MutableNode] = [:]
            var notes: [Note] = []
        }
        let root = MutableNode()
        for note in notes {
            guard let path = NoteFolderPath.normalize(note.folderPath) else { continue }
            let components = path.split(separator: "/").map(String.init)
            var cursor = root
            for component in components {
                if cursor.children[component] == nil { cursor.children[component] = MutableNode() }
                cursor = cursor.children[component]!
            }
            cursor.notes.append(note)
        }
        func emit(_ node: MutableNode, prefix: String) -> [FolderNode] {
            node.children.keys
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { name in
                    let child = node.children[name]!
                    let fullPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
                    return FolderNode(
                        id: fullPath,
                        name: name,
                        children: emit(child, prefix: fullPath),
                        notes: child.notes
                    )
                }
        }
        return emit(root, prefix: "")
    }
}
