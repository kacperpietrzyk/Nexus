import NexusCore
import NexusUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
#endif

/// The native block editor for a single `Note` (spec §5). Title field + a
/// properties/metadata panel (tags, type, timestamps) + an ordered stack of
/// per-block render/edit views, an "insert block" menu, a wikilink/embed picker,
/// and a backlinks panel. Mac + iOS; the Watch projection is separate.
struct NoteEditorView: View {  // swiftlint:disable:this type_body_length
    @Environment(\.noteRepository) private var noteRepository
    @State private var model: NoteEditorModel
    @State private var pickerContext: PickerContext?
    @State private var backlinks: [BacklinkEntry] = []
    @State private var newTag: String = ""
    @State private var folderText: String = ""
    @State private var newPropertyKey: String = ""
    @State private var imageImporterPresented = false
    @State private var imageImportError: String?
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    // O4 daily-note navigation: adjacent EXISTING daily notes + today check.
    @State private var previousDailyNoteID: UUID?
    @State private var nextDailyNoteID: UUID?
    @State private var isTodaysNote = true

    private let note: Note
    /// Navigate to another note's editor (spec §10 "klik → otwórz obiekt").
    /// Owned by the list's `NavigationStack`, so a Note→Note open pushes onto the
    /// shared path. Cross-feature targets (Task/Project) are not wired here — see
    /// `openRef`.
    private let onOpenNote: (UUID) -> Void
    /// Open the local graph centered on this note (O1). nil means the host has
    /// not wired the graph surface, so the row stays hidden.
    private let onOpenGraph: ((UUID) -> Void)?

    init(
        note: Note,
        onOpenNote: @escaping (UUID) -> Void = { _ in },
        onOpenGraph: ((UUID) -> Void)? = nil
    ) {
        self.note = note
        self.onOpenNote = onOpenNote
        self.onOpenGraph = onOpenGraph
        // The repository is read from the environment in `body`; the model is
        // rebuilt with it on appear so persistence is wired.
        _model = State(initialValue: NoteEditorModel(note: note, repository: nil))
    }

    var body: some View {
        ScrollViewReader { _ in
            editorList
        }
        .navigationTitle(model.title.isEmpty ? "Untitled" : model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: note.id) { rebindModel() }
        #if os(iOS)
        .task(id: selectedPhotoItem) {
            await handleSelectedPhotoItem(selectedPhotoItem)
        }
        #endif
        .toolbar {
            ToolbarItemGroup {
                #if os(iOS)
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityLabel("Insert image")
                .disabled(!model.canEdit)

                Menu {
                    Button("Insert image file") {
                        imageImporterPresented = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More image import options")
                .disabled(!model.canEdit)
                #else
                Button {
                    imageImporterPresented = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityLabel("Insert image")
                .disabled(!model.canEdit)
                #endif
            }
        }
        .fileImporter(
            isPresented: $imageImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleImageImport(result)
        }
        .alert(
            "Image import failed",
            isPresented: Binding(
                get: { imageImportError != nil },
                set: { if !$0 { imageImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { imageImportError = nil }
        } message: {
            Text(imageImportError ?? "")
        }
        .sheet(item: $pickerContext) { context in
            LinkPickerView(
                noteRepository: noteRepository,
                excludingNoteID: note.id
            ) { candidate in
                model.insertLink(to: candidate, asEmbed: context.asEmbed, after: context.afterID)
                pickerContext = nil
            }
        }
    }

    // MARK: - Sections

    /// The block list. On macOS it is hosted as a Liquid glass document panel
    /// (the platform `List` background is hidden so the glass shows through);
    /// iOS keeps the platform-native list. Same rows, same interactions.
    private var editorList: some View {
        let list = List {
            if model.role == .dailyNote {
                dailyNoteNavRow
            }
            titleField
            propertiesSection
            blockRows
            insertRow
            if !backlinks.isEmpty {
                backlinksSection
            }
        }
        .listStyle(.plain)
        #if os(macOS)
        return
            list
            .scrollContentBackground(.hidden)
            .padding(.vertical, DS.Space.s)
            .liquidLightCard(cornerRadius: DS.Radius.l)
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.l)
        #else
        return list
        #endif
    }

    private var titleField: some View {
        // Document title heading (not a form field): keep the display font — a
        // tile-boxed NexusTextField would flatten the page title.
        TextField("Title", text: $model.title)
            .textFieldStyle(.plain)
            .font(DS.FontToken.displayMedium)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .disabled(!model.canEdit)
            .onSubmit { model.commitTitle() }
            .listRowSeparator(.hidden)
    }

    /// Obsidian-style properties/metadata panel (A3 + Tranche 2 Plan E): editable
    /// tag chips, an editable folder path, read-only type and timestamps, then the
    /// structured custom property bag (key/value rows + an "add property" field)
    /// persisted via `NoteRepository.updateProperties`.
    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + 2) {
            propertyRow(label: "Tags") {
                tagEditor
            }
            propertyRow(label: "Folder") {
                folderEditor
            }
            propertyRow(label: "Type") {
                Text(roleLabel)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            propertyRow(label: "Created") {
                Text(model.createdAt, format: .dateTime.day().month().year())
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
            propertyRow(label: "Updated") {
                Text(model.updatedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
            if let onOpenGraph {
                propertyRow(label: "Graph") {
                    Button {
                        onOpenGraph(note.id)
                    } label: {
                        SwiftUI.Label(
                            "View local graph",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        .font(DS.FontToken.metadata)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .accessibilityLabel("View local graph for this note")
                }
            }
            customPropertyRows
            if model.canEdit {
                addPropertyField
            }
        }
        .padding(DS.Space.m)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.ColorToken.glassSoft)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
        .padding(.vertical, DS.Space.s)
        .listRowSeparator(.hidden)
    }

    private func propertyRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(label.uppercased())
                .font(DS.FontToken.caption)
                .kerning(0.6)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.tags.isEmpty {
                FlowChips(tags: model.tags) { tag in
                    if model.canEdit { model.removeTag(tag) }
                }
            }
            if model.canEdit {
                HStack(spacing: 6) {
                    Image(systemName: "number")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    tagInputField
                }
            }
        }
    }

    /// The "add tag" text field. iOS-only autocorrect/capitalization suppression is
    /// applied here (outside the `HStack` chain) so no `#if` sits mid-modifier-chain.
    private var tagInputField: some View {
        let field = NexusTextField("Add tag", text: $newTag, isEnabled: model.canEdit)
            .onSubmit { commitTag() }
        #if os(iOS)
        return
            field
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #else
        return field
        #endif
    }

    private var roleLabel: String {
        switch model.role {
        case .free: return "Note"
        case .projectPage: return "Project Page"
        case .dailyNote: return "Daily Note"
        case .template: return "Template"
        }
    }

    private func commitTag() {
        let value = newTag
        newTag = ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addTag(value)
    }

    // MARK: - Folder + custom properties (Tranche 2 Plan E)

    /// Editable folder path. Commits on submit through the model (which
    /// normalizes); the field re-seeds from the normalized result.
    private var folderEditor: some View {
        Group {
            if model.canEdit {
                folderInputField
            } else {
                Text(model.folderPath ?? "No folder")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
        }
    }

    private var folderInputField: some View {
        let field = NexusTextField("No folder", text: $folderText, isEnabled: model.canEdit)
            .onSubmit { commitFolder() }
        #if os(iOS)
        return
            field
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #else
        return field
        #endif
    }

    private func commitFolder() {
        model.setFolderPath(folderText.isEmpty ? nil : folderText)
        folderText = model.folderPath ?? ""
    }

    /// Editable key/value property rows (Tranche 2 Plan E, spec §4.4). Rows are
    /// identified by key — keys are unique case-sensitively (`NotePropertyEditing`
    /// enforces at the edit seam).
    private var customPropertyRows: some View {
        ForEach(model.properties, id: \.key) { property in
            NotePropertyRowView(
                property: property,
                canEdit: model.canEdit,
                onRenameKey: { model.renameProperty(property.key, to: $0) },
                onSetValue: { model.setPropertyValue($0, forKey: property.key) },
                onRemove: { model.removeProperty(property.key) }
            )
        }
    }

    private var addPropertyField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
            NexusTextField("Add property", text: $newPropertyKey)
                .onSubmit {
                    model.addProperty(key: newPropertyKey)
                    newPropertyKey = ""
                }
        }
    }

    private var blockRows: some View {
        ForEach(model.blocks) { block in
            BlockView(block: block, model: model, onOpenRef: { openRef($0) })
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    if model.canEdit {
                        Button(role: .destructive) {
                            model.remove(id: block.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        }
        .onMove { offsets, destination in
            model.move(from: offsets, to: destination)
        }
    }

    @ViewBuilder private var insertRow: some View {
        if model.canEdit {
            Menu {
                Button("Text") { model.insert(.paragraph, after: lastBlockID) }
                Button("Heading") { model.insert(.heading(level: 2), after: lastBlockID) }
                Button("To-do") { model.insert(.todo, after: lastBlockID) }
                Button("Bulleted list") { model.insert(.bulleted, after: lastBlockID) }
                Button("Numbered list") { model.insert(.numbered, after: lastBlockID) }
                Button("Quote") { model.insert(.quote, after: lastBlockID) }
                Button("Code") { model.insert(.code, after: lastBlockID) }
                Button("Divider") { model.insert(.divider, after: lastBlockID) }
                Divider()
                Button("Link to…") {
                    pickerContext = PickerContext(afterID: lastBlockID, asEmbed: false)
                }
                Button("Embed…") {
                    pickerContext = PickerContext(afterID: lastBlockID, asEmbed: true)
                }
            } label: {
                Label("Add block", systemImage: "plus.circle")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .listRowSeparator(.hidden)
        }
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("BACKLINKS")
                .font(DS.FontToken.caption)
                .kerning(0.6)
                .foregroundStyle(DS.ColorToken.textTertiary)
            ForEach(backlinks) { entry in
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    Text(entry.title)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(DS.Space.m)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(DS.ColorToken.glassSoft)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
        .padding(.top, DS.Space.m)
        .listRowSeparator(.hidden)
    }

    // MARK: - Daily-note navigation (O4)

    /// Prev/next-day chevrons between EXISTING daily notes (gaps are skipped,
    /// edges disable) + a "Today" jump that open-or-creates today's note when
    /// this note is not today's. Only mounted for `role == .dailyNote`.
    private var dailyNoteNavRow: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                if let previousDailyNoteID { onOpenNote(previousDailyNoteID) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(previousDailyNoteID == nil)
            .help("Previous daily note")
            .accessibilityLabel("Previous daily note")

            Button {
                if let nextDailyNoteID { onOpenNote(nextDailyNoteID) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(nextDailyNoteID == nil)
            .help("Next daily note")
            .accessibilityLabel("Next daily note")

            Spacer(minLength: 0)

            if !isTodaysNote {
                Button {
                    openTodaysDailyNote()
                } label: {
                    Label("Today", systemImage: "calendar")
                        .font(DS.FontToken.metadata)
                }
                .buttonStyle(.borderless)
                .help("Open today's note")
                .accessibilityLabel("Open today's note")
            }
        }
        .foregroundStyle(DS.ColorToken.textSecondary)
        .listRowSeparator(.hidden)
    }

    private func reloadDailyNavigation() {
        guard note.role == .dailyNote, let noteRepository else {
            previousDailyNoteID = nil
            nextDailyNoteID = nil
            isTodaysNote = true
            return
        }
        let service = DailyNoteService(repository: noteRepository)
        previousDailyNoteID =
            (try? service.adjacentDailyNote(from: note, direction: .previous))?.id
        nextDailyNoteID =
            (try? service.adjacentDailyNote(from: note, direction: .next))?.id
        isTodaysNote = service.day(of: note) == Calendar.current.startOfDay(for: Date.now)
    }

    private func openTodaysDailyNote() {
        guard let noteRepository else { return }
        guard
            let today = try? DailyNoteService(repository: noteRepository)
                .openOrCreate(for: Date.now)
        else { return }
        onOpenNote(today.id)
    }

    private var lastBlockID: UUID? { model.blocks.last?.id }

    // MARK: - Image import

    private func handleImageImport(_ result: Result<[URL], any Error>) {
        do {
            guard let source = try result.get().first else { return }
            let accessing = source.startAccessingSecurityScopedResource()
            defer {
                if accessing { source.stopAccessingSecurityScopedResource() }
            }
            guard let noteRepository else { return }
            let importer = NoteImageImporter(
                noteRepository: noteRepository,
                attachmentRoot: try NoteAttachmentRoot.url()
            )
            _ = try importer.importImage(from: source, into: note, after: lastBlockID)
            rebindModel()
        } catch {
            imageImportError = String(describing: error)
        }
    }

    #if os(iOS)
    private func handleSelectedPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhotoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let temporaryURL = try NotePhotosImageWriter.writeTemporaryPNGData(data)
            handleImageImport(.success([temporaryURL]))
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            imageImportError = String(describing: error)
        }
    }
    #endif

    // MARK: - Wiring

    /// Open a tapped embed / wikilink target (spec §10). A Note target pushes onto
    /// the shared navigation path (same `navigationDestination(for: UUID.self)`).
    /// Task / Project / Section targets need cross-feature navigation that this
    /// package can't reach without importing other features — left unwired (the
    /// inline preview already renders; opening those is a follow-up).
    private func openRef(_ ref: UUID) {
        guard let snapshot = model.embedSnapshot(for: ref) else { return }
        if snapshot.kind == .note {
            onOpenNote(ref)
        }
    }

    private func rebindModel() {
        model = NoteEditorModel(note: note, repository: noteRepository)
        folderText = model.folderPath ?? ""
        reloadBacklinks()
        reloadDailyNavigation()
    }

    private func reloadBacklinks() {
        guard let noteRepository else {
            backlinks = []
            return
        }
        let links = (try? noteRepository.backlinks(to: (.note, note.id))) ?? []
        backlinks = links.compactMap { link in
            guard let snapshot = try? noteRepository.embedSnapshot(for: link.fromID) else {
                return nil
            }
            return BacklinkEntry(id: link.id, title: snapshot.title)
        }
    }
}
