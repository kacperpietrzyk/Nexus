import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Watch read-only plain-text projection of the Notes content layer (spec §5/§9.9).
/// The Watch has no block editor — it renders the denormalized `Note.plainText`
/// cache (no block-blob deserialization on the wrist). A list of notes, newest
/// first; tapping shows the full plain text.
struct WatchNotesView: View {
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.updatedAt,
        order: .reverse
    )
    private var notes: [Note]

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView("No notes", systemImage: "note.text")
                    .foregroundStyle(NexusColor.Text.secondary)
            } else {
                List(notes) { note in
                    NavigationLink {
                        WatchNoteDetailView(note: note)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.headline)
                                .foregroundStyle(NexusColor.Text.primary)
                                .lineLimit(1)
                            if !preview(note).isEmpty {
                                Text(preview(note))
                                    .font(.caption2)
                                    .foregroundStyle(NexusColor.Text.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes")
    }

    private func preview(_ note: Note) -> String {
        note.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Full read-only plain-text view of a single note on the Watch.
struct WatchNoteDetailView: View {
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.headline)
                        .foregroundStyle(NexusColor.Text.primary)
                }
                Text(note.plainText)
                    .font(.body)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
    }
}
