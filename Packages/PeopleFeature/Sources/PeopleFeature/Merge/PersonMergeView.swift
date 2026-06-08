import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Merge UI (spec §4.3 / §6): pick a duplicate `Person` and fold it INTO the
/// `target`, calling `PersonRepository.mergePeople(into:from:)`. The picked
/// duplicate's graph edges are repointed onto the target, its aliases/fields are
/// merged, and it is soft-deleted — atomically (invariant I2). Candidates are
/// ranked name/alias-match-first by `PeopleListFiltering.mergeCandidates`.
public struct PersonMergeView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.dismiss) private var dismiss

    let target: Person

    @Query(
        filter: #Predicate<Person> { $0.deletedAt == nil },
        sort: \Person.displayName,
        order: .forward
    )
    private var people: [Person]

    @State private var searchText = ""
    @State private var pendingDuplicate: Person?
    @State private var mergeError: String?

    public init(target: Person) {
        self.target = target
    }

    private var candidates: [Person] {
        let ranked = PeopleListFiltering.mergeCandidates(for: target, among: people)
        return PeopleListFiltering.filter(ranked, query: searchText)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    NexusEmptyState(
                        systemImage: "person.2",
                        title: "No other people",
                        message: "There is no duplicate to merge into this contact."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Merge into \(target.displayName.isEmpty ? "this contact" : target.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { pendingDuplicate != nil },
                    set: { if !$0 { pendingDuplicate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Merge", role: .destructive) { performMerge() }
                Button("Cancel", role: .cancel) { pendingDuplicate = nil }
            } message: {
                Text("The duplicate's meetings, tasks, notes and details move onto \(targetName). The duplicate is removed.")
            }
            .alert(
                "Couldn't merge",
                isPresented: Binding(
                    get: { mergeError != nil },
                    set: { if !$0 { mergeError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { mergeError = nil }
            } message: {
                Text(mergeError ?? "")
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(candidates) { candidate in
                    Button {
                        pendingDuplicate = candidate
                    } label: {
                        PersonListRow(person: candidate)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Pick the duplicate to fold into \(targetName).")
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search duplicates")
    }

    private var targetName: String {
        target.displayName.isEmpty ? "this contact" : target.displayName
    }

    private var confirmationTitle: String {
        guard let pendingDuplicate else { return "Merge" }
        let name = pendingDuplicate.displayName.isEmpty ? "this contact" : pendingDuplicate.displayName
        return "Merge \(name) into \(targetName)?"
    }

    private func performMerge() {
        guard let personRepository, let duplicate = pendingDuplicate else { return }
        do {
            try personRepository.mergePeople(into: target, from: duplicate)
            pendingDuplicate = nil
            dismiss()
        } catch {
            mergeError = error.localizedDescription
            pendingDuplicate = nil
        }
    }
}
