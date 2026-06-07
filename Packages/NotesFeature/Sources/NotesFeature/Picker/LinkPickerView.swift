import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Autocomplete picker for wikilink + embed targets (spec §5/§9). Candidates are
/// the linkable objects resolvable in-store (notes, tasks, projects); the user
/// filters by title and picks one. The chosen target is stored by **id**, never by
/// title (rename-safe). Candidate gathering uses `@Query` so it tracks the live
/// store; ranking is the pure `LinkPickerFiltering`.
struct LinkPickerView: View {
    let noteRepository: NoteRepository?
    let excludingNoteID: UUID
    let onPick: (LinkCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var notes: [Note]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }) private var projects: [Project]

    var body: some View {
        NavigationStack {
            List(filtered) { candidate in
                Button {
                    onPick(candidate)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: glyph(candidate.kind))
                            .foregroundStyle(NexusColor.Text.tertiary)
                        Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                            .nexusType(.body)
                            .foregroundStyle(NexusColor.Text.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(kindLabel(candidate.kind))
                            .nexusType(.eyebrow)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search by title")
            .navigationTitle("Link to…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var candidates: [LinkCandidate] {
        var result: [LinkCandidate] = []
        result.reserveCapacity(notes.count + tasks.count + projects.count)
        for note in notes where note.id != excludingNoteID {
            result.append(LinkCandidate(id: note.id, kind: .note, title: note.title))
        }
        for task in tasks {
            result.append(LinkCandidate(id: task.id, kind: .task, title: task.title))
        }
        for project in projects {
            result.append(LinkCandidate(id: project.id, kind: .project, title: project.name))
        }
        return result
    }

    private var filtered: [LinkCandidate] {
        LinkPickerFiltering.filter(candidates, query: query)
    }

    private func glyph(_ kind: ItemKind) -> String {
        switch kind {
        case .note: return "note.text"
        case .task: return "checkmark.square"
        case .project: return "folder"
        default: return "doc"
        }
    }

    private func kindLabel(_ kind: ItemKind) -> String {
        switch kind {
        case .note: return "Note"
        case .task: return "Task"
        case .project: return "Project"
        default: return ""
        }
    }
}
