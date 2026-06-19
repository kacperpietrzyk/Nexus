import NexusCore
import SwiftUI

// MARK: - Shared alert chrome (macOS + iOS)

/// Applies the three shared alerts (note-error, new-folder, rename-folder) to
/// any host view. Extracted from `NotesListView` so macOS (`macOSRoot`) and iOS
/// (`body` stack) don't duplicate alert code. Callers own `.task`/`.onReceive`.
struct NotesSharedChrome: ViewModifier {
    @Binding var newNoteError: String?
    @Binding var moveToNewFolderNote: Note?
    @Binding var newFolderText: String
    @Binding var folderRenameTarget: String?
    @Binding var folderRenameText: String
    let onMoveNote: (Note, String?) -> Void
    let onRenameFolder: (String) -> Void

    func body(content: Content) -> some View {
        content
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
                    if let note = moveToNewFolderNote { onMoveNote(note, newFolderText) }
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
                    if let target = folderRenameTarget { onRenameFolder(target) }
                    folderRenameTarget = nil
                }
            } message: {
                Text("Notes in this folder and its subfolders move with it.")
            }
    }
}
