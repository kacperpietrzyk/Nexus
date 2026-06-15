import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes surface: a grouped list of all live notes (the free-note knowledge
/// base — spec §1, free notes are first-class), with a "New Note" affordance, a
/// grouping picker (role / tag), and navigation into the block editor. Mac + iOS;
/// the Watch projection is a separate bespoke view in the Watch app target.
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

    // The whole Link table, folded once into a per-note backlink count map (A5).
    // One query beats N per-row `FetchDescriptor<Link>` fetches on the main actor
    // during scroll (the documented hot-path rule). `toKind` is an enum stored
    // field that doesn't filter reliably in `#Predicate`, so we fold in memory.
    @Query private var links: [GraphLink]

    @State private var path: [UUID] = []
    @State private var newNoteError: String?
    @State private var groupMode: NoteListGrouping.Mode = .role
    @State private var showingTrash = false

    public init() {}

    private var backlinkCounts: [UUID: Int] {
        NoteListGrouping.backlinkCounts(from: links)
    }

    private var groups: [NoteListGrouping.Group] {
        NoteListGrouping.groups(for: notes, mode: groupMode)
    }

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
                ToolbarItem(placement: .automatic) {
                    Picker("Group by", selection: $groupMode) {
                        Label("Type", systemImage: "square.stack.3d.up")
                            .tag(NoteListGrouping.Mode.role)
                        Label("Tag", systemImage: "number")
                            .tag(NoteListGrouping.Mode.tag)
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingTrash = true
                    } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
            }
            .sheet(isPresented: $showingTrash) {
                NotesTrashView(noteRepository: noteRepository)
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
            ForEach(groups) { group in
                Section {
                    ForEach(group.notes) { note in
                        NavigationLink(value: note.id) {
                            NoteListRow(note: note, backlinkCount: backlinkCounts[note.id] ?? 0)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteNote(note)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    sectionHeader(group)
                }
            }
        }
        .listStyle(.plain)
    }

    private func sectionHeader(_ group: NoteListGrouping.Group) -> some View {
        HStack(spacing: 7) {
            Text(group.title)
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusCount(value: group.notes.count, font: NexusType.metaMono)
            Spacer(minLength: 0)
        }
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

    private func deleteNote(_ note: Note) {
        try? noteRepository?.delete(note)
    }
}

/// A single row in the notes list: a role glyph + title, a one-line preview drawn
/// from the denormalized `plainText` cache (never the block blob — spec §4.1), and
/// a metadata strip of tag chips + an optional backlink count.
struct NoteListRow: View {
    let note: Note
    let backlinkCount: Int

    private var tags: [String] {
        NoteListGrouping.normalizedTags(note.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                roleGlyph
                Text(displayTitle)
                    .nexusType(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if backlinkCount > 0 {
                    backlinkBadge
                }
            }
            if !preview.isEmpty {
                Text(preview)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.muted)
                    .lineLimit(1)
            }
            if !tags.isEmpty {
                tagStrip
            }
        }
        .padding(.vertical, 2)
    }

    private var backlinkBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusCount(value: backlinkCount, font: NexusType.metaMono)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(backlinkCount) backlinks"))
    }

    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    NexusChip(tag, systemImage: "number")
                }
            }
        }
        .scrollDisabled(tags.count <= 3)
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
