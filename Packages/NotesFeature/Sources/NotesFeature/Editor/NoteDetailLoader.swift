import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Resolves a `Note` by id from the live store and hands it to the editor. A
/// loader (rather than passing the `Note` directly through `navigationDestination`)
/// keeps the editor bound to a SwiftData-tracked instance in the current context,
/// and runs `reconcileOnLoad` to repair any blob↔graph drift from a crash between
/// save-blob and write-mirror (spec §6.2).
struct NoteDetailLoader: View {
    @Environment(\.noteRepository) private var noteRepository
    let noteID: UUID
    let onOpenNote: (UUID) -> Void

    @Query private var notes: [Note]

    init(noteID: UUID, onOpenNote: @escaping (UUID) -> Void = { _ in }) {
        self.noteID = noteID
        self.onOpenNote = onOpenNote
        _notes = Query(filter: #Predicate<Note> { $0.id == noteID && $0.deletedAt == nil })
    }

    var body: some View {
        if let note = notes.first {
            NoteEditorView(note: note, onOpenNote: onOpenNote)
                .task(id: note.id) {
                    _ = try? noteRepository?.reconcileOnLoad(note)
                }
        } else {
            NexusEmptyState(
                systemImage: "questionmark.folder",
                title: "Note not found",
                message: "It may have been deleted."
            )
        }
    }
}
