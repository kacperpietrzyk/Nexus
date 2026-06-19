// swiftlint:disable file_length
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
    #else
    @Environment(\.notesTaskRepository) private var notesTaskRepository
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

    // Path hoist (Task 8): macOS shell passes a binding (breadcrumb owns back +
    // deep-links); iOS leaves it nil → internal @State. `path` is `[UUID]`-typed
    // with a `nonmutating set` so every `path.append`/`removeAll` site is verbatim;
    // only the two real-`Binding` (`$path`) sites become `pathBinding`.
    @State private var internalPath: [UUID] = []
    private let externalPath: Binding<[UUID]>?
    private var path: [UUID] {
        get { externalPath?.wrappedValue ?? internalPath }
        nonmutating set {
            if let externalPath { externalPath.wrappedValue = newValue } else { internalPath = newValue }
        }
    }
    private var pathBinding: Binding<[UUID]> { Binding(get: { path }, set: { path = $0 }) }
    // macOS breadcrumb feed: deepest path id + title, `(nil, nil)` at root.
    private let onActiveNoteChange: ((UUID?, String?) -> Void)?

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
    @State private var showingTrash = false

    #if !os(macOS)
    // Multi-select (iOS only — macOS tree does its own wiring).
    @State private var selection = SelectionModel<UUID>()
    @State private var undo = UndoController()
    // Bulk-move target folder; triggers folder-picker sheet.
    @State private var bulkMovePickerShown = false
    #endif

    /// `path` nil → internal `@State` (iOS + legacy); the macOS shell passes a
    /// binding to hoist back/deep-link control. `onActiveNoteChange` is macOS-only.
    public init(
        path externalPath: Binding<[UUID]>? = nil,
        onActiveNoteChange: ((UUID?, String?) -> Void)? = nil
    ) {
        self.externalPath = externalPath
        self.onActiveNoteChange = onActiveNoteChange
    }

    private var backlinkCounts: [UUID: Int] {
        NoteListGrouping.backlinkCounts(from: links)
    }

    private var groups: [NoteListGrouping.Group] {
        NoteListGrouping.groups(for: notes, mode: groupMode)
    }

    public var body: some View {
        NavigationStack(path: pathBinding) {
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
            // Publish the breadcrumb leaf for the shell: deepest path id + its
            // title (resolved from the loaded `notes`), or `(nil, nil)` at root.
            .onChange(of: path, initial: true) { _, newPath in
                let lastID = newPath.last
                let title = lastID.flatMap { id in notes.first(where: { $0.id == id })?.title }
                onActiveNoteChange?(lastID, (title?.isEmpty ?? true) ? nil : title)
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingTrash = true
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(selection.isSelecting ? "Done" : "Select") {
                        if selection.isSelecting {
                            selection.exitSelection()
                        } else {
                            selection.enterSelection()
                        }
                    }
                    .disabled(notes.isEmpty)
                }
            }
            .sheet(isPresented: $showingTrash) {
                NotesTrashView(noteRepository: noteRepository)
            }
            .sheet(isPresented: $bulkMovePickerShown) {
                iosBulkMovePicker
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
                NotesTreeView(path: pathBinding, onOpenGraph: { openGraph(scope: .global) })
            }
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
            #if os(macOS)
            // Fresh daily-note open replaces the stack so the breadcrumb reads
            // `Notes › <day>` (not a deep drill); linked-note drill still appends.
            path = [note.id]
            #else
            path.append(note.id)
            #endif
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

// MARK: - iOS composition + bulk actions

#if !os(macOS)
extension NotesListView {

    // MARK: - iOS list

    @ViewBuilder var iosContent: some View {
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
                            Button {
                                if selection.isSelecting { selection.toggle(id: note.id) } else { path.append(note.id) }
                            } label: {
                                NoteListRow(note: note, backlinkCount: backlinkCounts[note.id] ?? 0)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .selectable(
                                isSelecting: selection.isSelecting,
                                isSelected: selection.isSelected(id: note.id),
                                onToggle: { selection.toggle(id: note.id) }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteNote(note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    try? noteRepository?.setPinned(note, !note.isPinned)
                                } label: {
                                    Label(
                                        note.isPinned ? "Unpin" : "Pin to Today",
                                        systemImage: note.isPinned ? "star.slash" : "star"
                                    )
                                }
                                .tint(note.isPinned ? .gray : .yellow)
                            }
                            .contextMenu {
                                noteRowContextMenu(note)
                            }
                        }
                    } header: {
                        sectionHeader(group)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            // Touch Liquid pass: transparent list on a single light-glass panel
            // over the shell aurora (mirrors Tasks + the `LiquidTodayScreen` card
            // family), inset so the aurora reads at the margins.
            .scrollContentBackground(.hidden)
            .background {
                Color.clear
                    .liquidLightCard(cornerRadius: DS.Radius.l)
                    .padding(.horizontal, DS.Space.s)
                    .padding(.bottom, DS.Space.s)
            }
            .safeAreaInset(edge: .bottom) {
                BulkActionBar(model: selection, allIDs: notes.map(\.id), actions: iosBulkActions)
            }
            .undoToast(undo)
            // Global ⌘A + palette "Select All Items": select every visible note.
            .selectAllCommandTarget(in: selection, ids: notes.map(\.id))
            .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
                selection.enterSelection()
                selection.selectAll(notes.map(\.id))
            }
        }
    }

    @ViewBuilder private func noteRowContextMenu(_ note: Note) -> some View {
        Button(note.isPinned ? "Unpin from Today" : "Pin to Today") {
            try? noteRepository?.setPinned(note, !note.isPinned)
        }
        .disabled(noteRepository == nil)
        Button {
            PasteboardCopy.string(NoteMarkdownExport.markdown(for: note))
        } label: {
            Label("Copy as Markdown", systemImage: "doc.plaintext")
        }
        Button {
            PasteboardCopy.string(NoteMarkdownExport.wikilink(for: note))
        } label: {
            Label("Copy Link", systemImage: "link")
        }
        Button {
            convertToTask(note)
        } label: {
            Label("Convert to Task", systemImage: "checkmark.square")
        }
        .disabled(notesTaskRepository == nil)
        noteTemplateContextMenu(note)
        moveToFolderMenu(for: note)
    }

    // MARK: - iOS bulk actions

    var iosBulkActions: [BulkAction] {
        [
            BulkAction(label: "Pin to Today", systemImage: "star") {
                let ids = Array(selection.selectedIDs)
                let targets = notes.filter { ids.contains($0.id) }
                for note in targets { try? noteRepository?.setPinned(note, true) }
                selection.exitSelection()
            },
            BulkAction(label: "Move…", systemImage: "folder") {
                bulkMovePickerShown = true
            },
            BulkAction(label: "Copy as Markdown", systemImage: "doc.plaintext") {
                let ids = Array(selection.selectedIDs)
                let targets = notes.filter { ids.contains($0.id) }
                let markdown = MarkdownExport.list(targets.map { NoteMarkdownExport.markdown(for: $0) })
                PasteboardCopy.string(markdown)
                selection.exitSelection()
            },
            BulkAction(label: "Delete", systemImage: "trash", role: .destructive) {
                let ids = Array(selection.selectedIDs)
                let targets = notes.filter { ids.contains($0.id) }
                for note in targets { try? noteRepository?.delete(note) }
                selection.exitSelection()
                let count = targets.count
                undo.show(message: "Deleted \(count) note\(count == 1 ? "" : "s")") {
                    for note in targets { try? noteRepository?.restore(note) }
                }
            },
        ]
    }

    @ViewBuilder var iosBulkMovePicker: some View {
        NavigationStack {
            List {
                Button("No Folder") {
                    bulkMoveNotesToFolder(nil)
                    bulkMovePickerShown = false
                }
                ForEach(folderMovePaths, id: \.self) { folderPath in
                    Button(folderPath) {
                        bulkMoveNotesToFolder(folderPath)
                        bulkMovePickerShown = false
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { bulkMovePickerShown = false }
                }
            }
        }
    }

    func bulkMoveNotesToFolder(_ path: String?) {
        let ids = Array(selection.selectedIDs)
        let targets = notes.filter { ids.contains($0.id) }
        for note in targets { try? noteRepository?.setFolderPath(note, path) }
        selection.exitSelection()
    }

    func convertToTask(_ note: Note) {
        guard let notesTaskRepository else { return }
        let draft = NoteTaskConversion.draft(from: note)
        let task = TaskItem(title: draft.title, body: draft.body)
        do {
            try notesTaskRepository.insert(task)
            try noteRepository?.delete(note)
        } catch {
            // Insert failed: leave the note intact.
        }
    }

    func sectionHeader(_ group: NoteListGrouping.Group) -> some View {
        HStack(spacing: 7) {
            Text(group.title)
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusCount(value: group.notes.count, font: NexusType.metaMono)
            if groupMode == .folder, group.id != NoteListGrouping.noFolderGroupID {
                Menu {
                    Button("Rename Folder…") { promptRenameFolder(group.id) }
                    Button("Remove Folder (Keep Notes)", role: .destructive) { removeFolder(group.id) }
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
}
#endif
