import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes surface: a grouped list of all live notes (the free-note knowledge
/// base — spec §1, free notes are first-class), with a "New Note" affordance, a
/// grouping picker (role / tag), and navigation into the block editor. Mac + iOS;
/// the Watch projection is a separate bespoke view in the Watch app target.
///
/// macOS renders the Liquid composition: an in-panel header (grouping segmented
/// control + New Note CTA) above hover-responsive glass rows — the module
/// contributes NOTHING to the window toolbar (the Liquid shell owns that). iOS
/// keeps the platform-native `List` + navigation-bar toolbar.
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` — no separate container registration is needed.
public struct NotesListView: View {
    @Environment(\.noteRepository) private var noteRepository
    #if os(macOS)
    @Environment(\.modelContext) private var modelContext
    @Environment(\.notesGraphExternalTitles) private var graphExternalTitles
    #endif

    // All live notes, newest-edited first. `deletedAt == nil` excludes tombstones.
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.updatedAt,
        order: .reverse
    )
    private var notes: [Note]

    // The whole Link table, folded once into a per-note backlink count map (A5).
    // One query beats N per-row `FetchDescriptor<Link>` fetches on the main actor
    // during scroll (the documented hot-path rule). `toKind` is an enum stored
    // field that doesn't filter reliably in `#Predicate`, so we fold in memory.
    @Query private var links: [GraphLink]

    @State private var path: [UUID] = []
    @State private var newNoteError: String?
    @State private var groupMode: NoteListGrouping.Mode = .role
    #if os(macOS)
    @State private var graphModel: NoteGraphModel?
    #endif

    // Folder ops (Tranche 2 Plan E). Optional-backed alert pattern, same as
    // `newNoteError`.
    @State private var folderRenameTarget: String?
    @State private var folderRenameText = ""
    @State private var moveToNewFolderNote: Note?
    @State private var newFolderText = ""

    public init() {}

    private var backlinkCounts: [UUID: Int] {
        NoteListGrouping.backlinkCounts(from: links)
    }

    private var groups: [NoteListGrouping.Group] {
        NoteListGrouping.groups(for: notes, mode: groupMode)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            platformContent
                .navigationDestination(for: UUID.self) { id in
                    #if os(macOS)
                    NoteDetailLoader(
                        noteID: id,
                        onOpenNote: { path.append($0) },
                        onOpenGraph: { noteID in
                            path.removeAll()
                            openGraph(
                                scope: .local(
                                    center: GraphNodeID(.note, noteID),
                                    depth: 1
                                )
                            )
                        }
                    )
                    #else
                    NoteDetailLoader(noteID: id, onOpenNote: { path.append($0) })
                    #endif
                }
                .alert(
                    "Couldn't create note",
                    isPresented: Binding(
                        get: { newNoteError != nil },
                        set: { if !$0 { newNoteError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { newNoteError = nil }
                } message: {
                    Text(newNoteError ?? "")
                }
                .alert(
                    "New Folder",
                    isPresented: Binding(
                        get: { moveToNewFolderNote != nil },
                        set: { if !$0 { moveToNewFolderNote = nil } }
                    )
                ) {
                    TextField("Folder path", text: $newFolderText)
                    Button("Cancel", role: .cancel) { moveToNewFolderNote = nil }
                    Button("Move") {
                        if let note = moveToNewFolderNote {
                            moveNote(note, toFolder: newFolderText)
                        }
                        moveToNewFolderNote = nil
                    }
                } message: {
                    Text("Slash-separated path, e.g. projects/nexus.")
                }
                .alert(
                    "Rename Folder",
                    isPresented: Binding(
                        get: { folderRenameTarget != nil },
                        set: { if !$0 { folderRenameTarget = nil } }
                    )
                ) {
                    TextField("Folder path", text: $folderRenameText)
                    Button("Cancel", role: .cancel) { folderRenameTarget = nil }
                    Button("Rename") {
                        if let target = folderRenameTarget {
                            _ = try? noteRepository?.renameFolder(from: target, to: folderRenameText)
                        }
                        folderRenameTarget = nil
                    }
                } message: {
                    Text("Notes in this folder and its subfolders move with it.")
                }
                .task {
                    consumePendingDailyNoteRequest()
                    #if os(macOS)
                    consumePendingGraphRequest()
                    #endif
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .notesOpenDailyNote)
                ) { _ in
                    consumePendingDailyNoteRequest()
                }
                #if os(macOS)
            .onReceive(
                NotificationCenter.default.publisher(for: .notesOpenGraph)
            ) { _ in
                consumePendingGraphRequest()
            }
                #endif
        }
    }

    // MARK: - Platform composition

    @ViewBuilder private var platformContent: some View {
        #if os(macOS)
        liquidContent
        #else
        iosContent
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openTodaysDailyNote()
                    } label: {
                        Label("Today's Note", systemImage: "calendar")
                    }
                    .disabled(noteRepository == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .disabled(noteRepository == nil)
                }
                if !templateNotes.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(templateNotes) { template in
                                Button(template.title.isEmpty ? "Untitled template" : template.title) {
                                    createNoteFromTemplate(template)
                                }
                            }
                        } label: {
                            Label("New Note from Template", systemImage: "doc.on.doc")
                        }
                        .disabled(noteRepository == nil)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    NexusSelect(
                        selection: $groupMode,
                        options: [.role, .tag, .folder],
                        label: { mode in
                            switch mode {
                            case .role: return "Type"
                            case .tag: return "Tag"
                            case .folder: return "Folder"
                            }
                        },
                        accessibilityLabel: "Group by"
                    )
                }
            }
        #endif
    }

    #if os(macOS)

    // MARK: - macOS Liquid composition

    private var liquidContent: some View {
        VStack(spacing: 0) {
            if let graphModel {
                NoteGraphView(
                    model: graphModel,
                    onOpenNote: { id in
                        self.graphModel = nil
                        path.append(id)
                    },
                    onClose: { self.graphModel = nil }
                )
            } else {
                NotesTreeView(path: $path, onOpenGraph: { openGraph(scope: .global) })
            }
        }
    }

    #else

    // MARK: - iOS composition (platform-native List)

    @ViewBuilder private var iosContent: some View {
        if notes.isEmpty {
            NexusEmptyState(
                systemImage: "note.text",
                title: "No notes yet",
                message: "Capture a thought, draft a page, or link ideas together."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.notes) { note in
                            NavigationLink(value: note.id) {
                                NoteListRow(note: note, backlinkCount: backlinkCounts[note.id] ?? 0)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteNote(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                noteTemplateContextMenu(note)
                                moveToFolderMenu(for: note)
                            }
                        }
                    } header: {
                        sectionHeader(group)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func sectionHeader(_ group: NoteListGrouping.Group) -> some View {
        HStack(spacing: 7) {
            Text(group.title)
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusCount(value: group.notes.count, font: NexusType.metaMono)
            if groupMode == .folder, group.id != NoteListGrouping.noFolderGroupID {
                Menu {
                    Button("Rename Folder…") { promptRenameFolder(group.id) }
                    Button("Remove Folder (Keep Notes)", role: .destructive) {
                        removeFolder(group.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
                .accessibilityLabel("Folder actions for \(group.title)")
            }
            Spacer(minLength: 0)
        }
    }

    #endif

    // MARK: - Actions

    private var templateNotes: [Note] {
        notes.filter { $0.role == .template }
    }

    private func createNoteFromTemplate(_ template: Note) {
        guard let noteRepository else { return }
        do {
            let note = try noteRepository.instantiateTemplate(template)
            path.append(note.id)
        } catch {
            newNoteError = error.localizedDescription
        }
    }

    private func saveNoteAsTemplate(_ note: Note) {
        guard let noteRepository else { return }
        do {
            try noteRepository.updateFields(note, role: .template)
        } catch {
            newNoteError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func noteTemplateContextMenu(_ note: Note) -> some View {
        if note.role == .template {
            Button("New Note from Template") { createNoteFromTemplate(note) }
        } else if note.role == .free {
            Button("Save as Template") { saveNoteAsTemplate(note) }
        }
        // projectPage / dailyNote: role is structural — no template conversion.
    }

    private func createNote() {
        guard let noteRepository else { return }
        do {
            let note = try noteRepository.create(title: "", blocks: [])
            path.append(note.id)
        } catch {
            newNoteError = error.localizedDescription
        }
    }

    private func deleteNote(_ note: Note) {
        try? noteRepository?.delete(note)
    }

    // MARK: - Folder ops (Tranche 2 Plan E)

    /// Every existing folder path (including implied ancestors), from the
    /// derived tree — the move-menu target list.
    private var folderMovePaths: [String] {
        NoteFolderTree.build(paths: notes.map(\.folderPath)).allPaths
    }

    private func moveNote(_ note: Note, toFolder path: String?) {
        try? noteRepository?.setFolderPath(note, path)
    }

    private func promptNewFolder(for note: Note) {
        newFolderText = note.folderPath ?? ""
        moveToNewFolderNote = note
    }

    private func promptRenameFolder(_ path: String) {
        folderRenameText = path
        folderRenameTarget = path
    }

    private func removeFolder(_ path: String) {
        _ = try? noteRepository?.removeFolder(path)
    }

    /// "Move to Folder" submenu for a row context menu: root, every existing
    /// folder (tree order), and a "New Folder…" prompt. Available in ALL
    /// grouping modes — folder placement is note metadata, not a mode feature.
    @ViewBuilder
    private func moveToFolderMenu(for note: Note) -> some View {
        Menu("Move to Folder") {
            Button("No Folder") { moveNote(note, toFolder: nil) }
            if !folderMovePaths.isEmpty {
                Divider()
                ForEach(folderMovePaths, id: \.self) { path in
                    Button(path) { moveNote(note, toFolder: path) }
                }
            }
            Divider()
            Button("New Folder…") { promptNewFolder(for: note) }
        }
    }

    /// O4 "Today's note": idempotent open-or-create via `DailyNoteService`
    /// (shared identity with the agent's brief note), then push the editor.
    private func openTodaysDailyNote() {
        guard let noteRepository else { return }
        do {
            let note = try DailyNoteService(repository: noteRepository)
                .openOrCreate(for: Date.now)
            path.append(note.id)
        } catch {
            newNoteError = error.localizedDescription
        }
    }

    #if os(macOS)
    @MainActor private func openGraph(scope: GraphScope) {
        graphModel = NoteGraphModel.live(
            context: modelContext,
            externalTitles: { [graphExternalTitles] in graphExternalTitles?() ?? [:] },
            scope: scope
        )
    }

    @MainActor private func consumePendingGraphRequest() {
        guard GraphOpenRequest.shared.consume() else { return }
        path.removeAll()
        openGraph(scope: .global)
    }
    #endif

    private func consumePendingDailyNoteRequest() {
        guard DailyNoteOpenRequest.shared.consume() else { return }
        openTodaysDailyNote()
    }
}
