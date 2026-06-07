import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes surface: a list of all live notes (the free-note knowledge base —
/// spec §1, free notes are first-class), with a "New Note" affordance and
/// navigation into the block editor. Mac + iOS; the Watch projection is a separate
/// bespoke view in the Watch app target (read-only plain text).
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` — no separate container registration is needed.
public struct NotesListView: View {
    @Environment(\.noteRepository) private var noteRepository

    // All live notes, newest-edited first. `deletedAt == nil` excludes tombstones.
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.updatedAt,
        order: .reverse
    )
    private var notes: [Note]

    @State private var path: [UUID] = []
    @State private var newNoteError: String?

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if notes.isEmpty {
                    NexusEmptyState(
                        systemImage: "note.text",
                        title: "No notes yet",
                        message: "Capture a thought, draft a page, or link ideas together."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .disabled(noteRepository == nil)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                NoteDetailLoader(noteID: id, onOpenNote: { path.append($0) })
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
        }
    }

    private var list: some View {
        List {
            ForEach(notes) { note in
                NavigationLink(value: note.id) {
                    NoteListRow(note: note)
                }
            }
            .onDelete(perform: deleteNotes)
        }
        .listStyle(.plain)
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

    private func deleteNotes(at offsets: IndexSet) {
        guard let noteRepository else { return }
        for index in offsets {
            try? noteRepository.delete(notes[index])
        }
    }
}

/// A single row in the notes list: title (or a placeholder) + a one-line preview
/// drawn from the denormalized `plainText` cache (never the block blob — spec §4.1).
struct NoteListRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                roleGlyph
                Text(displayTitle)
                    .nexusType(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
            }
            if !preview.isEmpty {
                Text(preview)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        note.title.isEmpty ? "Untitled" : note.title
    }

    private var preview: String {
        note.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder private var roleGlyph: some View {
        switch note.role {
        case .free:
            EmptyView()
        case .projectPage:
            Image(systemName: "folder")
                .foregroundStyle(NexusColor.Text.tertiary)
                .font(.caption)
        case .dailyNote:
            Image(systemName: "calendar")
                .foregroundStyle(NexusColor.Text.tertiary)
                .font(.caption)
        }
    }
}
