#if os(macOS)

import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// macOS knowledge-base navigator (spec §4): in-panel header + a sectioned,
/// nested tree (Unfiled / Projects / Library / Journal / Templates). Selecting a
/// note drives the shared `NavigationStack` into the existing block editor.
/// Selecting a note navigates; a per-note context menu and the header New Folder
/// button drive mutations (new folder, move, convert-to-task).
struct NotesTreeView: View {
    @Environment(\.noteRepository) private var noteRepository
    @Environment(\.notesTaskRepository) private var taskRepository

    @State private var newFolderText = ""
    @State private var showNewFolderAlert = false
    @State private var moveTarget: Note?
    @State private var moveFolderText = ""

    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }, sort: \Note.updatedAt, order: .reverse)
    private var notes: [Note]

    @Query private var links: [GraphLink]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil && $0.archivedAt == nil })
    private var activeProjects: [Project]

    @Binding var path: [UUID]
    var onOpenGraph: (() -> Void)?

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
        .alert("New folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderText)
            Button("Create") {
                createNote(in: NoteFolderPath.normalize(newFolderText))
                newFolderText = ""
            }
            Button("Cancel", role: .cancel) { newFolderText = "" }
        }
        .alert(
            "Move to folder",
            isPresented: Binding(
                get: { moveTarget != nil },
                set: { if !$0 { moveTarget = nil } }
            )
        ) {
            TextField("Folder path (blank = Unfiled)", text: $moveFolderText)
            Button("Move") {
                if let target = moveTarget {
                    try? noteRepository?.setFolderPath(target, NoteFolderPath.normalize(moveFolderText))
                }
                moveTarget = nil
            }
            Button("Cancel", role: .cancel) { moveTarget = nil }
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
                onOpenGraph?()
            }
            .disabled(onOpenGraph == nil)
            .help("Graph view")
            LiquidIconButton(
                systemImage: "folder.badge.plus",
                accessibilityLabel: "New folder"
            ) {
                showNewFolderAlert = true
            }
            .disabled(noteRepository == nil)
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
                        onSelect: select,
                        noteMenu: noteContextMenu
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
                    templateLeaf(note)
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
        .contextMenu { noteContextMenu(note) }
    }

    /// Template-specific row: tap or context-menu to instantiate a new note from
    /// this template. Does NOT offer Move/Convert-to-Task/Delete — template rows
    /// are structural, not knowledge notes to convert.
    private func templateLeaf(_ note: Note) -> some View {
        NoteTreeLeaf(
            note: note,
            isCanonical: false,
            isSelected: note.id == selection
        )
        .onTapGesture { instantiateTemplate(note) }
        .contextMenu {
            Button("New Note from Template") { instantiateTemplate(note) }
        }
    }

    private func instantiateTemplate(_ template: Note) {
        guard let created = try? noteRepository?.instantiateTemplate(template) else { return }
        select(created.id)
    }

    /// Shared per-note context menu used by both the flat-section leaves and the
    /// recursive Library `NoteFolderDisclosure`. Not offered on canonical project
    /// pages (Convert/Delete on a project's page would be wrong).
    @ViewBuilder private func noteContextMenu(_ note: Note) -> some View {
        Button("Move to folder…") {
            moveFolderText = note.folderPath ?? ""
            moveTarget = note
        }
        Button("Convert to Task") { convertToTask(note) }
            .disabled(taskRepository == nil)
        Divider()
        Button("Delete", role: .destructive) { deleteNote(note) }
    }

    @ViewBuilder private func treeSection<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let key = "\u{0}sec:\(title)"
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsed.contains(key) },
                set: { setCollapsed(key, !$0) }
            )
        ) {
            content()
        } label: {
            Text(title.uppercased())
                .font(NexusType.metaMono)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .kerning(0.6)
                .padding(.horizontal, DS.Space.xs)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xxs)
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

    private func convertToTask(_ note: Note) {
        guard let taskRepository else { return }
        let draft = NoteTaskConversion.draft(from: note)
        let task = TaskItem(title: draft.title, body: draft.body)
        // Gate the delete on a successful insert: with two independent `try?`s the
        // note would be soft-deleted even when the task insert throws — silent data
        // loss, since the tree `@Query` filters out `deletedAt != nil` notes.
        do {
            try taskRepository.insert(task)
            try noteRepository?.delete(note)
            if path.last == note.id { path = [] }  // selection is derived from path.last
        } catch {
            // Insert failed: leave the note intact rather than destroy it.
        }
    }

    private func deleteNote(_ note: Note) {
        try? noteRepository?.delete(note)
        if path.last == note.id { path = [] }  // selection is derived from path.last
    }
}

#endif
