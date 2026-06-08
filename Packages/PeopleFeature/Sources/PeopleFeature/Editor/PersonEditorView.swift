import NexusCore
import NexusUI
import SwiftUI

/// Field editor for a `Person` (spec §6): displayName / aliases / email / phone /
/// company / note. Writes route exclusively through `PersonRepository.update` —
/// there is deliberately NO assignee field (invariant I1; `Person` is never a task
/// owner) and the repository exposes no such parameter.
public struct PersonEditorView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.dismiss) private var dismiss

    let person: Person

    @State private var displayName: String
    @State private var aliasesText: String
    @State private var email: String
    @State private var phone: String
    @State private var company: String
    @State private var note: String
    @State private var saveError: String?

    public init(person: Person) {
        self.person = person
        _displayName = State(initialValue: person.displayName)
        _aliasesText = State(initialValue: person.aliases.joined(separator: ", "))
        _email = State(initialValue: person.email ?? "")
        _phone = State(initialValue: person.phone ?? "")
        _company = State(initialValue: person.company ?? "")
        _note = State(initialValue: person.note ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $displayName)
                    TextField("Aliases (comma-separated)", text: $aliasesText)
                }
                Section("Contact") {
                    TextField("Email", text: $email)
                        #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                        #endif
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                    .keyboardType(.phonePad)
                        #endif
                    TextField("Company", text: $company)
                }
                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Person")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(personRepository == nil)
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func save() {
        guard let personRepository else { return }
        let parsedAliases =
            aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try personRepository.update(
                person,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                aliases: parsedAliases,
                email: optional(email),
                phone: optional(phone),
                company: optional(company),
                note: optional(note)
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Maps an empty/whitespace field to `nil` (clears the value) and a non-empty
    /// field to its trimmed text. Wrapped in the double-optional the repository's
    /// `update` expects, so passing it always applies the change.
    private func optional(_ text: String) -> String?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Optional(trimmed.isEmpty ? nil : trimmed)
    }
}
