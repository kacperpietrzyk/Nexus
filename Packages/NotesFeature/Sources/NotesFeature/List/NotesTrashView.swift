import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes trash (spec §8): a list of soft-deleted notes (`deletedAt != nil`)
/// with a per-row Restore action wired to `NoteRepository.restore`. Recovery was
/// otherwise MCP-only (`items.restore`); this surfaces it in-app. Mirrors
/// `NotesListView` styling — same `NoteListRow`, same plain list — minus grouping
/// and the backlink count (tombstones carry no live edges).
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
                NoteListRow(note: note, backlinkCount: 0)
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
