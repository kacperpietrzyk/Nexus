import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// A compact inline autocomplete dropdown shown beneath a text block while the user
/// is typing a `[[query` wikilink trigger (GAP #6, spec §5/§9). Candidates are the
/// linkable objects in-store (notes/tasks/projects), filtered by the live query and
/// ranked by the pure `LinkPickerFiltering` — the same source as the full
/// `LinkPickerView`. Picking one stores the target by id (rename-safe). Candidate
/// gathering uses `@Query` so it tracks the live store.
struct InlineLinkAutocomplete: View {
    let query: String
    let excludingNoteID: UUID
    let onPick: (LinkCandidate) -> Void

    @Query(filter: #Predicate<Note> { $0.deletedAt == nil }) private var notes: [Note]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }) private var projects: [Project]

    /// At most a handful of rows so the dropdown stays inline (not a full sheet).
    private let limit = 5

    var body: some View {
        let results = Array(filtered.prefix(limit))
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { candidate in
                    Button {
                        onPick(candidate)
                    } label: {
                        row(candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                NexusColor.Background.control,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r1)
                    .stroke(NexusColor.Line.strong, lineWidth: 0.5)
            )
        }
    }

    private func row(_ candidate: LinkCandidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: glyph(candidate.kind))
                .font(.system(size: 11))
                .foregroundStyle(NexusColor.Text.tertiary)
            Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(kindLabel(candidate.kind))
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
