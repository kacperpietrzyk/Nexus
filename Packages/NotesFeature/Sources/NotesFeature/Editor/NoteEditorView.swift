import NexusCore
import NexusUI
import SwiftUI

/// The native block editor for a single `Note` (spec §5). Title field + an ordered
/// stack of per-block render/edit views, an "insert block" menu, a wikilink/embed
/// picker, and a backlinks panel. Mac + iOS; the Watch projection is separate.
struct NoteEditorView: View {
    @Environment(\.noteRepository) private var noteRepository
    @State private var model: NoteEditorModel
    @State private var pickerContext: PickerContext?
    @State private var backlinks: [BacklinkEntry] = []

    private let note: Note
    /// Navigate to another note's editor (spec §10 "klik → otwórz obiekt").
    /// Owned by the list's `NavigationStack`, so a Note→Note open pushes onto the
    /// shared path. Cross-feature targets (Task/Project) are not wired here — see
    /// `openRef`.
    private let onOpenNote: (UUID) -> Void

    init(note: Note, onOpenNote: @escaping (UUID) -> Void = { _ in }) {
        self.note = note
        self.onOpenNote = onOpenNote
        // The repository is read from the environment in `body`; the model is
        // rebuilt with it on appear so persistence is wired.
        _model = State(initialValue: NoteEditorModel(note: note, repository: nil))
    }

    var body: some View {
        ScrollViewReader { _ in
            List {
                titleField
                blockRows
                insertRow
                if !backlinks.isEmpty {
                    backlinksSection
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(model.title.isEmpty ? "Untitled" : model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: note.id) { rebindModel() }
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

    private var titleField: some View {
        TextField("Title", text: $model.title)
            .textFieldStyle(.plain)
            .font(NexusType.h2)
            .foregroundStyle(NexusColor.Text.primary)
            .disabled(!model.canEdit)
            .onSubmit { model.commitTitle() }
            .listRowSeparator(.hidden)
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
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            .menuStyle(.borderlessButton)
            .listRowSeparator(.hidden)
        }
    }

    private var backlinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backlinks")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            ForEach(backlinks) { entry in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    Text(entry.title)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 16)
        .listRowSeparator(.hidden)
    }

    private var lastBlockID: UUID? { model.blocks.last?.id }

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
        reloadBacklinks()
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

private struct PickerContext: Identifiable {
    let id = UUID()
    let afterID: UUID?
    let asEmbed: Bool
}

private struct BacklinkEntry: Identifiable {
    let id: UUID
    let title: String
}
