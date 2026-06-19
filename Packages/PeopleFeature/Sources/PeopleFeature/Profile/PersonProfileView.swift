import NexusCore
import NexusUI
import SwiftData
import SwiftUI

#if os(macOS)
/// Readable single-column width for the profile on the wide Mac content panel —
/// visual calibration (no DS column token); matches the People list column.
private let profileColumnMaxWidth: CGFloat = 720
#endif

/// "Show me everything about X" (spec §1, §6): a person's contact fields plus the
/// graph-aggregated meeting history (`.attendee`), mentioning tasks and mentioning
/// notes (`.mentions`) — one reverse-query, no manual bridging (spec §7).
///
/// Liquid: contact + aggregate sections sit on glass cards; on macOS the
/// back/edit/merge actions live in the in-panel header (never window-toolbar
/// items — the Liquid shell owns the window chrome). iOS keeps the navigation
/// bar.
///
/// Cross-module resolution asymmetry (spec §6 / CLAUDE.md isolation): `TaskItem`
/// and `Note` live in NexusCore so this view fetches them directly by id;
/// `Meeting` lives in NexusMeetings (un-importable here) so meeting rows are
/// resolved through the host-injected `\.personMeetingResolver`.
public struct PersonProfileView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.personMeetingResolver) private var meetingResolver
    @Environment(\.onCreateLinkedTask) private var onCreateLinkedTask
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let personID: UUID

    @State private var person: Person?
    @State private var meetingRows: [any Linkable] = []
    @State private var taskRows: [any Linkable] = []
    @State private var noteRows: [any Linkable] = []
    @State private var editorPresented = false
    @State private var mergePresented = false
    @State private var deleteConfirmPresented = false
    @State private var loadError: String?

    public init(personID: UUID) {
        self.personID = personID
    }

    public var body: some View {
        ScrollView {
            if let person {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    header(person)
                    contactFields(person)
                    aggregateSection(
                        title: "Meetings",
                        systemImage: "person.2",
                        emptyMessage: "No meetings linked yet.",
                        rows: meetingRows
                    )
                    aggregateSection(
                        title: "Tasks",
                        systemImage: "checkmark.circle",
                        emptyMessage: "No tasks mention this person.",
                        rows: taskRows
                    )
                    aggregateSection(
                        title: "Notes",
                        systemImage: "doc.text",
                        emptyMessage: "No notes mention this person.",
                        rows: noteRows
                    )
                }
                .padding(DS.Space.xl)
                #if os(macOS)
                .frame(maxWidth: profileColumnMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                #else
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            } else {
                LiquidEmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    message: loadError ?? "Person not found."
                )
                .padding(DS.Space.xxxl)
            }
        }
        #if os(iOS)
        .navigationTitle(person?.displayName.isEmpty == false ? person!.displayName : "Person")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let current = person, let email = current.email, !email.isEmpty {
                    Button {
                        PasteboardCopy.string(email)
                    } label: {
                        Label("Copy Email", systemImage: "envelope")
                    }
                }

                if onCreateLinkedTask != nil, let current = person {
                    Button {
                        onCreateLinkedTask?(current)
                    } label: {
                        Label("New Linked Task", systemImage: "checkmark.circle.badge.plus")
                    }
                }

                Button {
                    mergePresented = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(person == nil || personRepository == nil)

                Button {
                    editorPresented = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(person == nil || personRepository == nil)

                Button(role: .destructive) {
                    deleteConfirmPresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(person == nil || personRepository == nil)
            }
        }
        #endif
        .sheet(isPresented: $editorPresented, onDismiss: reload) {
            if let person {
                PersonEditorView(person: person)
            }
        }
        .sheet(isPresented: $mergePresented, onDismiss: reload) {
            if let person {
                PersonMergeView(target: person)
            }
        }
        .confirmationDialog(
            "Delete \(person?.displayName.isEmpty == false ? person!.displayName : "this person")?",
            isPresented: $deleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deletePerson() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the contact and all graph links to their meetings, tasks, and notes. This action cannot be undone."
            )
        }
        .task(id: personID) { reload() }
    }

    @ViewBuilder
    private func header(_ person: Person) -> some View {
        HStack(spacing: DS.Space.m) {
            LiquidAvatar(name: person.displayName, size: 48)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(person.displayName.isEmpty ? "Unnamed" : person.displayName)
                    .font(DS.FontToken.displayMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                if let company = person.company, !company.isEmpty {
                    Text(company)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }

            Spacer(minLength: 0)

            #if os(macOS)
            if let email = person.email, !email.isEmpty {
                LiquidIconButton(systemImage: "envelope", accessibilityLabel: "Copy Email") {
                    PasteboardCopy.string(email)
                }
            }
            if onCreateLinkedTask != nil {
                LiquidIconButton(
                    systemImage: "checkmark.circle.badge.plus",
                    accessibilityLabel: "New Linked Task"
                ) {
                    onCreateLinkedTask?(person)
                }
            }
            LiquidIconButton(systemImage: "arrow.triangle.merge", accessibilityLabel: "Merge") {
                mergePresented = true
            }
            .disabled(personRepository == nil)
            LiquidIconButton(systemImage: "pencil", accessibilityLabel: "Edit") {
                editorPresented = true
            }
            .disabled(personRepository == nil)
            LiquidIconButton(systemImage: "trash", accessibilityLabel: "Delete") {
                deleteConfirmPresented = true
            }
            .disabled(personRepository == nil)
            #endif
        }
    }

    private func deletePerson() {
        guard let personRepository, let person else { return }
        try? personRepository.softDelete(person)
        dismiss()
    }

    @ViewBuilder
    private func contactFields(_ person: Person) -> some View {
        let fields = PersonProfileFields.fields(for: person)
        if !fields.isEmpty {
            LiquidGlassCard("Contact") {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .font(DS.FontToken.caption)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                            Text(field.value)
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func aggregateSection(
        title: String,
        systemImage: String,
        emptyMessage: String,
        rows: [any Linkable]
    ) -> some View {
        LiquidGlassCard(title) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .padding(.vertical, DS.Space.xxs)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(rows, id: \.id) { row in
                        LiquidLinkableRow(
                            title: row.title,
                            systemImage: systemImage,
                            updatedAt: row.updatedAt
                        )
                    }
                }
            }
        }
    }

    private func reload() {
        guard let personRepository else { return }
        do {
            guard let loaded = try personRepository.find(id: personID), loaded.deletedAt == nil else {
                person = nil
                loadError = "This contact may have been deleted."
                return
            }
            person = loaded
            let aggregate = try personRepository.aggregate(loaded)
            taskRows = try PersonAggregateResolver.resolveTasks(ids: aggregate.tasks, in: modelContext)
                .map { $0 as any Linkable }
            noteRows = try PersonAggregateResolver.resolveNotes(ids: aggregate.notes, in: modelContext)
                .map { $0 as any Linkable }
            meetingRows = resolveMeetings(ids: aggregate.meetings)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func resolveMeetings(ids: [UUID]) -> [any Linkable] {
        guard let meetingResolver else { return [] }
        return ids.compactMap { meetingResolver.resolve($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// One aggregate row inside a profile card: kind glyph + title + relative
/// timestamp. Display-only (matches the pre-Liquid profile, whose rows were not
/// interactive); the section header already names the kind, so the glyph is
/// decorative.
private struct LiquidLinkableRow: View {
    let title: String
    let systemImage: String
    let updatedAt: Date

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: systemImage)
                // 11 pt glyph rides the 13 pt body line (Liquid metadata-glyph
                // scale); no icon-size token.
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.Space.s)
            Text(updatedAt, style: .relative)
                .font(DS.FontToken.metadata)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .padding(.vertical, DS.Space.xxs)
    }
}
