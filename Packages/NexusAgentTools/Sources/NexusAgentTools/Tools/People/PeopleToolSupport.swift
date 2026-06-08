import Foundation
import NexusCore
import SwiftData

/// Shared argument parsing + the structural single-user boundary for the `people.*`
/// MCP tools (People/Contacts module, spec §7).
///
/// ## Invariant I1 is structural, not validated
/// `people.link` never accepts a free-form `LinkKind`. It accepts an `object_kind`
/// restricted to `meeting | task | note` and DERIVES the edge label from
/// `PersonSourceKind` (`meeting → .attendee`, `task/note → .mentions`). There is no
/// arg the agent can set that would make a `Person` a task assignee — the only
/// `task ↔ person` edge any code path here can emit is `.mentions` (spec §5 I1).
enum PeopleToolSupport {
    /// Resolves a live (non-soft-deleted) `Person` by UUID, throwing `notFound`.
    @MainActor
    static func livePerson(id: UUID, context: AgentContext) throws -> Person {
        guard let person = try context.personRepository.find(id: id), person.deletedAt == nil else {
            throw AgentError.notFound("Person not found: \(id.uuidString)")
        }
        return person
    }

    /// Whether a LIVE person already exists for `externalSourceID` (used to report
    /// created-vs-updated on the idempotent upsert without adding a repo method). A
    /// soft-deleted tombstone keeps its `externalSourceID` but does not count as live —
    /// matching the repo's upsert, which re-creates after a delete.
    @MainActor
    static func liveExists(externalSourceID: String, context: AgentContext) throws -> Bool {
        let descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { person in person.externalSourceID == externalSourceID }
        )
        return try context.modelContext.context.fetch(descriptor).contains { $0.deletedAt == nil }
    }

    /// Parses an `object_kind` string into a `PersonSourceKind` — the ONLY kinds a
    /// person may be linked from (meeting/task/note). Any other value is rejected, so
    /// there is no path to link a person to an arbitrary endpoint or as an assignee.
    static func sourceKind(_ value: JSONValue?) throws -> PersonSourceKind {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: object_kind")
        }
        switch text {
        case "meeting": return .meeting
        case "task": return .task
        case "note": return .note
        default:
            throw AgentError.validation(
                "object_kind must be one of: meeting, task, note (a person is linked as a meeting "
                    + "attendee or as a task/note mention — never an assignee)."
            )
        }
    }

    static func optionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string")
        }
        return text
    }

    /// Parses a `field` that may be present-with-a-value, present-as-null, or absent.
    /// Returns `.some(.some(value))` for a string, `.some(.none)` for explicit JSON
    /// null (clear the field), and `.none` for an omitted key (leave untouched).
    static func nullableString(_ value: JSONValue?, field: String) throws -> String?? {
        guard let value else { return .none }
        if case .null = value { return .some(.none) }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string or null")
        }
        return .some(.some(text))
    }

    static func requiredString(_ value: JSONValue?, field: String) throws -> String {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        return text
    }

    static func requiredUUID(_ value: JSONValue?, field: String) throws -> UUID {
        let text = try requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a valid UUID")
        }
        return id
    }

    static func aliases(_ value: JSONValue?) throws -> [String]? {
        guard let value else { return nil }
        guard let values = value.arrayValue else {
            throw AgentError.validation("aliases must be an array of strings")
        }
        return try values.enumerated().map { index, element in
            guard let alias = element.stringValue else {
                throw AgentError.validation("aliases[\(index)] must be a string")
            }
            return alias
        }
    }

    /// In-tool live-`Person` fetch with optional case/diacritic-insensitive substring
    /// match over `searchableText` (display name + aliases + company). Kept
    /// dependency-free (a direct `FetchDescriptor<Person>`), mirroring `NotesQuery` —
    /// global `SearchIndex` wiring is search-foundation scope (§9), not tool scope.
    @MainActor
    static func fetch(
        context: AgentContext,
        searchableContains: String?,
        limit: Int
    ) throws -> [Person] {
        var descriptor = FetchDescriptor<Person>(
            sortBy: [SortDescriptor(\.displayName, order: .forward)]
        )
        descriptor.predicate = #Predicate { $0.deletedAt == nil }

        let needle = searchableContains.map(fold)
        var results: [Person] = []
        for person in try context.modelContext.context.fetch(descriptor) {
            if let needle, !needle.isEmpty {
                guard fold(person.searchableText).contains(needle) else { continue }
            }
            results.append(person)
            if results.count >= limit { break }
        }
        return results
    }

    /// Case/diacritic-insensitive fold for substring matching (mirrors the repo).
    static func fold(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
