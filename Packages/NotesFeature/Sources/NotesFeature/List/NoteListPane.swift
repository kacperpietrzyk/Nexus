#if os(macOS)

import NexusCore
import NexusUI
import SwiftUI

/// The right-pane root of the two-pane Notes surface: a rich, scannable list of
/// `LiquidNoteRow`s for the currently-selected `NoteContainer`. Selecting a row
/// opens the editor (the host pushes it onto the shared navigation path).
struct NoteListPane: View {
    let container: NoteContainer
    let tree: NoteTreeModel.Tree
    let allNotes: [Note]
    let backlinkCounts: [UUID: Int]
    let onOpenNote: (UUID) -> Void
    let onDeleteNote: (Note) -> Void
    var extraContextMenu: ((Note) -> AnyView)?

    private var result: NoteListResolver.Result {
        NoteListResolver.resolve(container: container, tree: tree, allNotes: allNotes)
    }

    var body: some View {
        Group {
            if result.sections.allSatisfy({ $0.notes.isEmpty }) {
                NexusEmptyState(
                    systemImage: "note.text",
                    title: title,
                    message: "Nothing here yet."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.l) {
                        ForEach(result.sections) { section in
                            sectionView(section)
                        }
                        if result.truncated {
                            Text("Showing the most recent notes.")
                                .font(DS.FontToken.metadata)
                                .foregroundStyle(DS.ColorToken.textMuted)
                                .padding(.horizontal, DS.Space.m)
                        }
                    }
                    .padding(.vertical, DS.Space.s)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func sectionView(_ section: NoteListResolver.Section) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if let title = section.title {
                Text(title.uppercased())
                    .font(NexusType.metaMono)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .kerning(0.6)
                    .padding(.horizontal, DS.Space.m)
            }
            ForEach(section.notes) { note in
                LiquidNoteRow(
                    note: note,
                    backlinkCount: backlinkCounts[note.id] ?? 0,
                    onOpen: { onOpenNote(note.id) },
                    onDelete: { onDeleteNote(note) },
                    extraContextMenu: extraContextMenu?(note)
                )
            }
        }
    }

    private var title: String {
        switch container {
        case .overview: return "Notes"
        case .unfiled: return "Unfiled"
        case .journal: return "Journal"
        case .templates: return "Templates"
        case .project: return "Project"
        case .folder(let path): return path
        }
    }
}

#endif
