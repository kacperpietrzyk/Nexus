import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Notes surface: a grouped list of all live notes (the free-note knowledge
/// base — spec §1, free notes are first-class), with a "New Note" affordance, a
/// grouping picker (role / tag), and navigation into the block editor. Mac + iOS;
/// the Watch projection is a separate bespoke view in the Watch app target.
///
/// macOS renders the Liquid composition: an in-panel header (grouping segmented
/// control + New Note CTA) above hover-responsive glass rows — the module
/// contributes NOTHING to the window toolbar (the Liquid shell owns that). iOS
/// keeps the platform-native `List` + navigation-bar toolbar.
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

    public init() {}

    private var backlinkCounts: [UUID: Int] {
        NoteListGrouping.backlinkCounts(from: links)
    }

    private var groups: [NoteListGrouping.Group] {
        NoteListGrouping.groups(for: notes, mode: groupMode)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            platformContent
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
                .task { consumePendingDailyNoteRequest() }
                .onReceive(
                    NotificationCenter.default.publisher(for: .notesOpenDailyNote)
                ) { _ in
                    consumePendingDailyNoteRequest()
                }
        }
    }

    // MARK: - Platform composition

    @ViewBuilder private var platformContent: some View {
        #if os(macOS)
        liquidContent
        #else
        iosContent
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openTodaysDailyNote()
                    } label: {
                        Label("Today's Note", systemImage: "calendar")
                    }
                    .disabled(noteRepository == nil)
                }
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
            }
        #endif
    }

    #if os(macOS)

    // MARK: - macOS Liquid composition

    private var liquidContent: some View {
        VStack(spacing: 0) {
            listHeader

            if notes.isEmpty {
                LiquidEmptyState(
                    systemImage: "note.text",
                    message: "Capture a thought, draft a page, or link ideas together."
                ) {
                    LiquidPrimaryButton("New Note", systemImage: "square.and.pencil") {
                        createNote()
                    }
                    .disabled(noteRepository == nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                liquidList
            }
        }
    }

    /// In-panel header: grouping control + New Note CTA. Replaces the old
    /// window-toolbar items, which leaked next to the traffic lights on macOS.
    private var listHeader: some View {
        HStack(spacing: DS.Space.m) {
            LiquidSegmentedControl(
                options: [
                    LiquidSegmentOption(NoteListGrouping.Mode.role, label: "Type"),
                    LiquidSegmentOption(NoteListGrouping.Mode.tag, label: "Tag"),
                ],
                selection: $groupMode
            )

            Spacer(minLength: DS.Space.m)

            LiquidIconButton(
                systemImage: "calendar",
                accessibilityLabel: "Open today's note"
            ) {
                openTodaysDailyNote()
            }
            .disabled(noteRepository == nil)
            .help("Open today's note (⌘⇧D)")

            LiquidPrimaryButton("New Note", systemImage: "square.and.pencil") {
                createNote()
            }
            .disabled(noteRepository == nil)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.s)
    }

    private var liquidList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                ForEach(groups) { group in
                    liquidSectionHeader(group)
                    ForEach(group.notes) { note in
                        LiquidNoteRow(
                            note: note,
                            backlinkCount: backlinkCounts[note.id] ?? 0,
                            onOpen: { path.append(note.id) },
                            onDelete: { deleteNote(note) }
                        )
                    }
                }
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.vertical, DS.Space.m)
        }
    }

    private func liquidSectionHeader(_ group: NoteListGrouping.Group) -> some View {
        HStack(spacing: DS.Space.xs) {
            Text(group.title.uppercased())
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .kerning(0.6)
            Text("\(group.notes.count)")
                .font(DS.FontToken.caption)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.xs)
    }

    #else

    // MARK: - iOS composition (platform-native List)

    @ViewBuilder private var iosContent: some View {
        if notes.isEmpty {
            NexusEmptyState(
                systemImage: "note.text",
                title: "No notes yet",
                message: "Capture a thought, draft a page, or link ideas together."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
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

    #endif

    // MARK: - Actions

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

    /// O4 "Today's note": idempotent open-or-create via `DailyNoteService`
    /// (shared identity with the agent's brief note), then push the editor.
    private func openTodaysDailyNote() {
        guard let noteRepository else { return }
        do {
            let note = try DailyNoteService(repository: noteRepository)
                .openOrCreate(for: Date.now)
            path.append(note.id)
        } catch {
            newNoteError = error.localizedDescription
        }
    }

    private func consumePendingDailyNoteRequest() {
        guard DailyNoteOpenRequest.shared.consume() else { return }
        openTodaysDailyNote()
    }
}

#if os(macOS)

/// A Liquid list row for one note: role glyph + title + trailing backlinks/date
/// metadata, a one-line preview from the denormalized `plainText` cache (never
/// the block blob — spec §4.1), and a strip of tag pills. Hover answers with a
/// fill wash only (dense list — no scale per the implementation guide).
private struct LiquidNoteRow: View {
    let note: Note
    let backlinkCount: Int
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    /// Row hover wash — same value family as `LiquidTaskRow` (white 4%).
    private static let hoverFill = Color.white.opacity(0.04)

    private var tags: [String] {
        NoteListGrouping.normalizedTags(note.tags)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                roleGlyph
                    .frame(width: 16, alignment: .center)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Space.s) {
                        Text(displayTitle)
                            .font(DS.FontToken.bodyStrong)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: DS.Space.s)

                        if backlinkCount > 0 {
                            backlinkBadge
                        }

                        Text(note.updatedAt, format: .relative(presentation: .named))
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .lineLimit(1)
                    }

                    if !preview.isEmpty {
                        Text(preview)
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .lineLimit(1)
                    }

                    if !tags.isEmpty {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(tags.prefix(4), id: \.self) { tag in
                                LiquidPill(tag, color: DS.ColorToken.accentCyan)
                            }
                            if tags.count > 4 {
                                Text("+\(tags.count - 4)")
                                    .font(DS.FontToken.caption)
                                    .foregroundStyle(DS.ColorToken.textMuted)
                            }
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(hovering ? Self.hoverFill : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(Text(displayTitle))
    }

    private var backlinkBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.turn.up.left")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
            Text("\(backlinkCount)")
                .font(DS.FontToken.caption)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(backlinkCount) backlinks"))
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
            Image(systemName: "note.text")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
        case .projectPage:
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        case .dailyNote:
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }
}

#endif

#if !os(macOS)

/// A single row in the notes list: a role glyph + title, a one-line preview drawn
/// from the denormalized `plainText` cache (never the block blob — spec §4.1), and
/// a metadata strip of tag chips + an optional backlink count. iOS only — macOS
/// renders `LiquidNoteRow`.
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

#endif
