import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// "Show me everything about X" (spec §1, §6): a person's contact fields plus the
/// graph-aggregated meeting history (`.attendee`), mentioning tasks and mentioning
/// notes (`.mentions`) — one reverse-query, no manual bridging (spec §7).
///
/// Cross-module resolution asymmetry (spec §6 / CLAUDE.md isolation): `TaskItem`
/// and `Note` live in NexusCore so this view fetches them directly by id;
/// `Meeting` lives in NexusMeetings (un-importable here) so meeting rows are
/// resolved through the host-injected `\.personMeetingResolver`.
public struct PersonProfileView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.personMeetingResolver) private var meetingResolver
    @Environment(\.modelContext) private var modelContext

    let personID: UUID

    @State private var person: Person?
    @State private var meetingRows: [any Linkable] = []
    @State private var taskRows: [any Linkable] = []
    @State private var noteRows: [any Linkable] = []
    @State private var editorPresented = false
    @State private var mergePresented = false
    @State private var loadError: String?

    public init(personID: UUID) {
        self.personID = personID
    }

    public var body: some View {
        ScrollView {
            if let person {
                VStack(alignment: .leading, spacing: 20) {
                    header(person)
                    contactFields(person)
                    aggregateSection(
                        title: "Meetings",
                        emptyMessage: "No meetings linked yet.",
                        rows: meetingRows
                    )
                    aggregateSection(
                        title: "Tasks",
                        emptyMessage: "No tasks mention this person.",
                        rows: taskRows
                    )
                    aggregateSection(
                        title: "Notes",
                        emptyMessage: "No notes mention this person.",
                        rows: noteRows
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NexusEmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "Person not found",
                    message: loadError
                )
                .padding(40)
            }
        }
        .navigationTitle(person?.displayName.isEmpty == false ? person!.displayName : "Person")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
            }
        }
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
        .task(id: personID) { reload() }
    }

    @ViewBuilder
    private func header(_ person: Person) -> some View {
        HStack(spacing: 14) {
            NexusAvatar(name: person.displayName, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(person.displayName.isEmpty ? "Unnamed" : person.displayName)
                    .nexusType(.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                if let company = person.company, !company.isEmpty {
                    Text(company)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func contactFields(_ person: Person) -> some View {
        let fields = PersonProfileFields.fields(for: person)
        if !fields.isEmpty {
            NexusCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contact")
                        .nexusType(.eyebrow)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.label)
                                .nexusType(.caption)
                                .foregroundStyle(NexusColor.Text.tertiary)
                            Text(field.value)
                                .nexusType(.bodySmall)
                                .foregroundStyle(NexusColor.Text.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func aggregateSection(title: String, emptyMessage: String, rows: [any Linkable]) -> some View {
        // Inlined rather than `BacklinksView` (which hardcodes its own "Backlinks"
        // eyebrow) so each section carries its own Meetings/Tasks/Notes header.
        // `ItemRow` is the same primitive `BacklinksView` renders internally.
        NexusCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
                if rows.isEmpty {
                    Text(emptyMessage)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.id) { row in
                            ItemRow(item: row)
                        }
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
