import Foundation
import NexusCore

/// A single labelled contact field row for the person profile (spec §4 / §6).
/// Pure value type so the profile's "which fields to show, in what order" rule is
/// unit-testable without driving SwiftUI.
public struct PersonContactField: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case email
        case phone
        case company
        case note
        case aliases
    }

    public var kind: Kind
    public var label: String
    public var value: String

    public var id: String { kind.rawValue }

    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

/// Pure derivation of the displayable contact fields for a `Person`, in a fixed
/// order, omitting empty values (spec §6 field editor mirrors this set:
/// displayName/aliases/email/phone/company/note). `displayName` is the profile
/// header, not a field row, so it is intentionally excluded here.
public enum PersonProfileFields {
    public static func fields(for person: Person) -> [PersonContactField] {
        var out: [PersonContactField] = []

        let email = trimmed(person.email)
        if !email.isEmpty { out.append(.init(kind: .email, label: "Email", value: email)) }

        let phone = trimmed(person.phone)
        if !phone.isEmpty { out.append(.init(kind: .phone, label: "Phone", value: phone)) }

        let company = trimmed(person.company)
        if !company.isEmpty { out.append(.init(kind: .company, label: "Company", value: company)) }

        let aliases = person.aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !aliases.isEmpty {
            out.append(.init(kind: .aliases, label: "Also known as", value: aliases.joined(separator: ", ")))
        }

        let note = trimmed(person.note)
        if !note.isEmpty { out.append(.init(kind: .note, label: "Note", value: note)) }

        return out
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
