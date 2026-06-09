import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The People surface (spec §6): a searchable list of all live `Person` contact
/// records with a "New Person" affordance and navigation into the profile. Mac +
/// iOS; the Watch projection is out of scope (slim Watch).
///
/// The list is grouped into sticky alphabetical sections; the junk auto-created
/// "Participant N" / "Speaker N" placeholder rows are suppressed from the main
/// list and revealed only via a collapsible "From meetings" section at the bottom
/// (view-layer cleanup — the root cause of placeholder creation is fixed
/// elsewhere). Each row carries a trailing meeting-count chip, resolved once in a
/// single batched fetch rather than per-row.
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` (where `Person` is already registered via `NexusSchemaV12`) —
/// no separate container registration is needed.
public struct PeopleListView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Person> { $0.deletedAt == nil },
        sort: \Person.displayName,
        order: .forward
    )
    private var people: [Person]

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var newPersonError: String?
    @State private var meetingCounts: [UUID: Int] = [:]
    @State private var fromMeetingsExpanded = false

    public init() {}

    private var model: PeopleListModel {
        PeopleListFiltering.sectionedModel(people, query: searchText)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if people.isEmpty {
                    NexusEmptyState(
                        systemImage: "person.crop.circle",
                        title: "No people yet",
                        message: "Add a contact, or they appear automatically from meetings."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createPerson()
                    } label: {
                        Label("New Person", systemImage: "person.badge.plus")
                    }
                    .disabled(personRepository == nil)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PersonProfileView(personID: id)
            }
            .alert(
                "Couldn't add person",
                isPresented: Binding(
                    get: { newPersonError != nil },
                    set: { if !$0 { newPersonError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { newPersonError = nil }
            } message: {
                Text(newPersonError ?? "")
            }
            .task(id: people.count) { reloadMeetingCounts() }
        }
    }

    private var list: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.people) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                    }
                    .onDelete { offsets in delete(from: section.people, at: offsets) }
                } header: {
                    sectionHeader(section.title)
                }
            }

            fromMeetingsSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search people")
    }

    @ViewBuilder
    private var fromMeetingsSection: some View {
        let placeholders = model.fromMeetings
        if !placeholders.isEmpty {
            Section {
                if fromMeetingsExpanded {
                    ForEach(placeholders) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                    }
                    .onDelete { offsets in delete(from: placeholders, at: offsets) }
                }
            } header: {
                Button {
                    withAnimation(.snappy(duration: 0.18)) { fromMeetingsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: fromMeetingsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("From meetings")
                        Spacer(minLength: 8)
                        NexusCount(value: placeholders.count)
                    }
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("From meetings, \(placeholders.count) hidden")
                .accessibilityHint(fromMeetingsExpanded ? "Hides auto-created people." : "Shows auto-created people.")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .nexusType(.eyebrow)
            .foregroundStyle(NexusColor.Text.muted)
    }

    private func createPerson() {
        guard let personRepository else { return }
        do {
            let person = try personRepository.create(displayName: "")
            path.append(person.id)
        } catch {
            newPersonError = error.localizedDescription
        }
    }

    private func delete(from rows: [Person], at offsets: IndexSet) {
        guard let personRepository else { return }
        for index in offsets where rows.indices.contains(index) {
            try? personRepository.softDelete(rows[index])
        }
    }

    /// One batched pass over the `Link` table to count attended meetings per person
    /// (powers the row chip). Re-run when the population changes; failures degrade
    /// to no chips rather than surfacing an error.
    private func reloadMeetingCounts() {
        meetingCounts = (try? PersonAggregateResolver.meetingCounts(in: modelContext)) ?? [:]
    }
}

/// A single row in the people list: avatar + display name + a Linear-style
/// secondary line (company · email) + a trailing meeting-count chip ("4
/// meetings"). The avatar stays achromatic (current design language).
struct PersonListRow: View {
    let person: Person
    /// Attended-meeting count for the trailing chip; resolved once via a batched
    /// fetch by the list. Defaults to 0 (no chip) for reuse sites — e.g. the merge
    /// picker — that have no count to show.
    var meetingCount: Int = 0

    var body: some View {
        HStack(spacing: 10) {
            NexusAvatar(name: displayName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .nexusType(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if meetingCount > 0 {
                NexusChip(meetingChipLabel)
                    .accessibilityLabel("\(meetingCount) \(meetingCount == 1 ? "meeting" : "meetings")")
            }
        }
        .padding(.vertical, 3)
    }

    private var displayName: String {
        person.displayName.isEmpty ? "Unnamed" : person.displayName
    }

    /// Secondary line: company/role joined with the first contact detail by a
    /// middot, mirroring Linear's dense metadata rows. Drops empty parts so a
    /// company-only or email-only person reads cleanly.
    private var subtitle: String {
        let company = person.company?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = [person.email, person.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return [company, contact]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var meetingChipLabel: String {
        meetingCount == 1 ? "1 meeting" : "\(meetingCount) meetings"
    }
}
