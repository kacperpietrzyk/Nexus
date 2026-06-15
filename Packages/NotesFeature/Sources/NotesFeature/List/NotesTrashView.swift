import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes trash (spec §8): a list of soft-deleted notes (`deletedAt != nil`)
/// with a per-row Restore action wired to `NoteRepository.restore`. Recovery was
/// otherwise MCP-only (`items.restore`); this surfaces it in-app. Uses a small
/// self-contained tombstone row (title + one-line preview) so it stays
/// cross-platform — the main list's `LiquidNoteRow`/`NoteListRow` are
/// platform-gated and carry open/delete affordances a trash list doesn't want.
struct NotesTrashView: View {
    /// Passed explicitly from the presenter (not read from `\.noteRepository` in the
    /// environment): the sheet-presenting precedent in this package — `LinkPickerView`
    /// — hands the repository in as a parameter rather than relying on the custom
    /// environment value crossing the sheet boundary, so we match it. (The
    /// `modelContainer` still propagates, so the `@Query` below works.)
    let noteRepository: NoteRepository?

    @Environment(\.dismiss) private var dismiss

    // Tombstones only, most-recently-deleted first. The `@Query` tracks the live
    // store, so a Restore drops the row immediately (its `deletedAt` clears).
    @Query(
        filter: #Predicate<Note> { $0.deletedAt != nil },
        sort: \Note.deletedAt,
        order: .reverse
    )
    private var deleted: [Note]

    var body: some View {
        NavigationStack {
            Group {
                if deleted.isEmpty {
                    NexusEmptyState(
                        systemImage: "trash",
                        title: "Trash is empty",
                        message: "Deleted notes appear here, where you can restore them."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(deleted) { note in
                TrashNoteRow(note: note)
                    .swipeActions(edge: .trailing) {
                        restoreButton(note)
                    }
                    .contextMenu {
                        restoreButton(note)
                    }
            }
        }
        .listStyle(.plain)
    }

    private func restoreButton(_ note: Note) -> some View {
        Button {
            restore(note)
        } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        .tint(NexusColor.Accent.lime)
        .disabled(noteRepository == nil)
    }

    private func restore(_ note: Note) {
        try? noteRepository?.restore(note)
    }
}

/// Minimal tombstone row: role-agnostic title + one-line preview from the
/// denormalized `plainText` cache (never the block blob — spec §4.1).
private struct TrashNoteRow: View {
    let note: Note

    private var displayTitle: String {
        note.title.isEmpty ? "Untitled" : note.title
    }

    private var preview: String {
        note.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .nexusType(.body)
                .fontWeight(.medium)
                .foregroundStyle(NexusColor.Text.primary)
                .lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
