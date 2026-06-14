#if os(macOS)

import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// macOS knowledge-base navigator (spec §4): in-panel header + a sectioned,
/// nested tree (Unfiled / Projects / Library / Journal / Templates). Selecting a
/// note drives the shared `NavigationStack` into the existing block editor.
/// Read/navigate only — mutations (new folder, move) come in Task 4.
struct NotesTreeView: View {
    @Environment(\.noteRepository) private var noteRepository

    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }, sort: \Note.updatedAt, order: .reverse)
    private var notes: [Note]

    @Query private var links: [GraphLink]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil && $0.archivedAt == nil })
    private var activeProjects: [Project]

    @Binding var path: [UUID]

    /// The currently-shown note, derived from the shared navigation `path` rather
    /// than held as standalone state. The same `NavigationStack` is mutated
    /// externally — the editor pushes linked notes via `path.append`, the graph
    /// flow clears via `path.removeAll` — so deriving keeps the tree highlight in
    /// sync with whatever is actually on screen (and degrades to nil off-tree).
    private var selection: UUID? { path.last }

    /// Serialised as newline-joined folder paths. A path in this set means the
    /// `DisclosureGroup` is collapsed (name is `collapsed` not `expanded` so the
    /// default empty-string value means everything is open on first launch).
    @AppStorage("notes.tree.collapsed") private var collapsedRaw = ""

    private var tree: NoteTreeModel.Tree {
        NoteTreeModel.build(
            notes: notes,
            links: links,
            projects: activeProjects.map {
                NoteTreeModel.ProjectRef(
                    id: $0.id,
                    title: $0.title,
                    canonicalNoteRef: $0.canonicalNoteRef
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                treeBody
                    .padding(DS.Space.s)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            Text("Notes")
                .font(DS.FontToken.title)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer()
            LiquidIconButton(
                systemImage: "point.3.connected.trianglepath.dotted",
                accessibilityLabel: "Open graph view"
            ) {
                // Task 5 wires graph navigation
            }
            .help("Graph view")
            LiquidIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "New folder"
            ) {
                // Task 4 wires folder creation
            }
            .help("New folder")
            LiquidIconButton(
                systemImage: "square.and.pencil",
                accessibilityLabel: "New note"
            ) {
                createNote(in: nil)
            }
            .disabled(noteRepository == nil)
            .help("New note")
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
    }

    // MARK: - Tree body

    @ViewBuilder private var treeBody: some View {
        if !tree.unfiled.isEmpty {
            treeSection("Unfiled") {
                ForEach(tree.unfiled) { note in
                    leaf(note)
                }
            }
        }
        if !tree.projects.isEmpty {
            treeSection("Projects") {
                ForEach(tree.projects) { proj in
                    projectDisclosure(proj)
                }
            }
        }
        if !tree.library.isEmpty {
            treeSection("Library") {
                ForEach(tree.library) { node in
                    NoteFolderDisclosure(
                        node: node,
                        selection: selection,
                        isExpanded: { !collapsed.contains($0) },
                        setExpanded: { setCollapsed($0, !$1) },
                        onSelect: select
                    )
                }
            }
        }
        if !tree.journal.isEmpty {
            treeSection("Journal") {
                ForEach(tree.journal) { note in
                    leaf(note)
                }
            }
        }
        if !tree.templates.isEmpty {
            treeSection("Templates") {
                ForEach(tree.templates) { note in
                    leaf(note)
                }
            }
        }
    }

    private func projectDisclosure(_ proj: NoteTreeModel.ProjectSection) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsed.contains(proj.id.uuidString) },
                set: { setCollapsed(proj.id.uuidString, !$0) }
            )
        ) {
            if let canonical = proj.canonical {
                NoteTreeLeaf(
                    note: canonical,
                    isCanonical: true,
                    isSelected: canonical.id == selection
                )
                .onTapGesture { select(canonical.id) }
            }
            ForEach(proj.notes) { note in
                leaf(note)
            }
        } label: {
            Label(proj.title, systemImage: "square.stack.3d.up")
                .font(DS.FontToken.bodyStrong)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
    }

    private func leaf(_ note: Note) -> some View {
        NoteTreeLeaf(
            note: note,
            isCanonical: false,
            isSelected: note.id == selection
        )
        .onTapGesture { select(note.id) }
    }

    @ViewBuilder private func treeSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title.uppercased())
                .font(NexusType.metaMono)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .kerning(0.6)
                .padding(.horizontal, DS.Space.xs)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xxs)
            content()
        }
    }

    // MARK: - Selection

    private func select(_ id: UUID) {
        path = [id]
    }

    // MARK: - Expansion persistence

    private var collapsed: Set<String> {
        Set(collapsedRaw.split(separator: "\n").map(String.init))
    }

    private func setCollapsed(_ key: String, _ isCollapsed: Bool) {
        var set = collapsed
        if isCollapsed {
            set.insert(key)
        } else {
            set.remove(key)
        }
        collapsedRaw = set.sorted().joined(separator: "\n")
    }

    // MARK: - Actions

    private func createNote(in folder: String?) {
        guard let noteRepository else { return }
        if let created = try? noteRepository.create() {
            if let folder {
                try? noteRepository.setFolderPath(created, folder)
            }
            select(created.id)
        }
    }
}

#endif
