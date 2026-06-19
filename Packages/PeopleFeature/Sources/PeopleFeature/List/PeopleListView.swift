import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The People surface (spec §6): a searchable list of all live `Person` contact
/// records with a "New Person" affordance and navigation into the profile. Mac +
/// iOS; the Watch projection is out of scope (slim Watch).
///
/// The list is grouped into alphabetical sections; the junk auto-created
/// "Participant N" / "Speaker N" placeholder rows are suppressed from the main
/// list and revealed only via a collapsible "From meetings" section at the bottom
/// (view-layer cleanup — the root cause of placeholder creation is fixed
/// elsewhere). Each row carries a trailing meeting-count label, resolved once in a
/// single batched fetch rather than per-row.
///
/// macOS renders the Liquid idiom: an in-panel search field + New Person action
/// (never window-toolbar items — the Liquid shell owns the window chrome) above a
/// hover-responsive row list. iOS keeps the native `List` + `.searchable` +
/// navigation-bar toolbar.
///
/// Multi-select: long-press any row to enter selection mode. A `BulkActionBar`
/// slides up from the bottom offering bulk delete. Soft-delete removes graph
/// edges, so undo is not offered (no safe restore path on `PersonRepository`).
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` (where `Person` is already registered via `NexusSchemaV12`) —
/// no separate container registration is needed.
public struct PeopleListView: View {
    @Environment(\.personRepository) var personRepository
    @Environment(\.onCreateLinkedTask) var onCreateLinkedTask
    @Environment(\.modelContext) var modelContext

    @Query(
        filter: #Predicate<Person> { $0.deletedAt == nil },
        sort: \Person.displayName,
        order: .forward
    )
    var people: [Person]

    // Path hoist (Task 9 navigation pass): macOS shell passes a binding so the
    // breadcrumb owns back and deep-links; iOS leaves it nil → internal @State.
    // `path` computed property with `nonmutating set` keeps every `path.append` /
    // `path.removeAll` call site byte-identical; only the real-Binding site uses
    // `pathBinding`.
    @State var internalPath: [UUID] = []
    private let externalPath: Binding<[UUID]>?
    var path: [UUID] {
        get { externalPath?.wrappedValue ?? internalPath }
        nonmutating set {
            if let externalPath { externalPath.wrappedValue = newValue } else { internalPath = newValue }
        }
    }
    var pathBinding: Binding<[UUID]> { Binding(get: { path }, set: { path = $0 }) }
    // macOS breadcrumb feed: deepest path id + display name, `(nil, nil)` at root.
    private let onActivePersonChange: ((UUID?, String?) -> Void)?

    @State var searchText = ""
    @State var newPersonError: String?
    @State var meetingCounts: [UUID: Int] = [:]
    @State var fromMeetingsExpanded = false
    @State var selection = SelectionModel<UUID>()

    /// `path` nil → internal `@State` (iOS + legacy); the macOS shell passes a
    /// binding to hoist back/deep-link control. `onActivePersonChange` is macOS-only.
    public init(
        path externalPath: Binding<[UUID]>? = nil,
        onActivePersonChange: ((UUID?, String?) -> Void)? = nil
    ) {
        self.externalPath = externalPath
        self.onActivePersonChange = onActivePersonChange
    }

    var model: PeopleListModel {
        PeopleListFiltering.sectionedModel(people, query: searchText)
    }

    public var body: some View {
        NavigationStack(path: pathBinding) {
            platformContent
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
                // Global ⌘A + palette "Select All Items": select every person.
                .selectAllCommandTarget(in: selection, ids: people.map(\.id))
                .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
                    selection.enterSelection()
                    selection.selectAll(people.map(\.id))
                }
                #if os(macOS)
            // Publish the breadcrumb leaf for the shell: deepest path id +
            // the person's displayName, or `(nil, nil)` at root.
            .onChange(of: path, initial: true) { _, newPath in
                let lastID = newPath.last
                let name = lastID.flatMap { id in people.first(where: { $0.id == id })?.displayName }
                onActivePersonChange?(lastID, (name?.isEmpty ?? true) ? nil : name)
            }
                #endif
        }
    }

    // Platform-specific views are in extensions below (macOS / iOS).

}

// MARK: - Context menu (extracted to keep PeopleListView under type_body_length limit)

extension PeopleListView {
    @ViewBuilder
    func personContextMenu(_ person: Person) -> some View {
        if let email = person.email, !email.isEmpty {
            Button {
                PasteboardCopy.string(email)
            } label: {
                Label("Copy Email", systemImage: "envelope")
            }
        }

        if onCreateLinkedTask != nil {
            Button {
                onCreateLinkedTask?(person)
            } label: {
                Label("New Linked Task", systemImage: "checkmark.circle.badge.plus")
            }
        }

        Divider()

        Button(role: .destructive) {
            softDeleteWithUndo(person)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Actions + bulk (extracted to keep PeopleListView under type_body_length limit)

extension PeopleListView {
    var bulkActions: [BulkAction] {
        [
            BulkAction(label: "Delete", systemImage: "trash", role: .destructive) {
                let ids = Array(selection.selectedIDs)
                let toDelete = people.filter { ids.contains($0.id) }
                guard let personRepository else {
                    selection.exitSelection()
                    return
                }
                for person in toDelete {
                    try? personRepository.softDelete(person)
                }
                selection.exitSelection()
                // Soft-delete removes graph edges — not safely reversible without a
                // restore(id:) on PersonRepository. No undo toast.
            }
        ]
    }

    func createPerson() {
        guard let personRepository else { return }
        do {
            let person = try personRepository.create(displayName: "")
            path.append(person.id)
        } catch {
            newPersonError = error.localizedDescription
        }
    }

    func softDeleteWithUndo(_ person: Person) {
        guard let personRepository else { return }
        try? personRepository.softDelete(person)
        // Soft-delete removes graph edges — not safely reversible without a
        // restore(id:) on PersonRepository. No undo toast.
    }

    /// One batched pass over the `Link` table to count attended meetings per person
    /// (powers the row's trailing label). Re-run when the population changes;
    /// failures degrade to no labels rather than surfacing an error.
    func reloadMeetingCounts() {
        meetingCounts = (try? PersonAggregateResolver.meetingCounts(in: modelContext)) ?? [:]
    }
}
