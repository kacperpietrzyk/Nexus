import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The People surface (spec §6): a searchable list of all live `Person` contact
/// records with a "New Person" affordance and navigation into the profile. Mac +
/// iOS; the Watch projection is out of scope (slim Watch).
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` (where `Person` is already registered via `NexusSchemaV12`) —
/// no separate container registration is needed.
public struct PeopleListView: View {
    @Environment(\.personRepository) private var personRepository

    @Query(
        filter: #Predicate<Person> { $0.deletedAt == nil },
        sort: \Person.displayName,
        order: .forward
    )
    private var people: [Person]

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var newPersonError: String?

    public init() {}

    private var visiblePeople: [Person] {
        PeopleListFiltering.filter(people, query: searchText)
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
        }
    }

    private var list: some View {
        List {
            ForEach(visiblePeople) { person in
                NavigationLink(value: person.id) {
                    PersonListRow(person: person)
                }
            }
            .onDelete(perform: deletePeople)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search people")
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

    private func deletePeople(at offsets: IndexSet) {
        guard let personRepository else { return }
        let rows = visiblePeople
        for index in offsets where rows.indices.contains(index) {
            try? personRepository.softDelete(rows[index])
        }
    }
}

/// A single row in the people list: avatar + display name + a one-line subtitle
/// (company, falling back to the first contact detail).
struct PersonListRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            NexusAvatar(name: displayName, size: 28)
            VStack(alignment: .leading, spacing: 2) {
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
        }
        .padding(.vertical, 2)
    }

    private var displayName: String {
        person.displayName.isEmpty ? "Unnamed" : person.displayName
    }

    private var subtitle: String {
        let candidates = [person.company, person.email, person.phone]
        return
            candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }
}
