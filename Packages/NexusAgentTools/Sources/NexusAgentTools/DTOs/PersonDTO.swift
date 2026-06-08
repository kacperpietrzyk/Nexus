import Foundation
import NexusCore

/// Wire format for a `Person` exposed via MCP (People/Contacts module, spec §7).
/// snake_case keys per MCP convention. A `Person` is a contact RECORD, never a task
/// assignee (invariant I1) — there is no assignee/owner field here by design.
public struct PersonDTO: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let aliases: [String]
    public let email: String?
    public let phone: String?
    public let company: String?
    public let note: String?
    public let externalSourceID: String?
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case aliases
        case email
        case phone
        case company
        case note
        case externalSourceID = "external_source_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        displayName: String,
        aliases: [String],
        email: String?,
        phone: String?,
        company: String?,
        note: String?,
        externalSourceID: String?,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.email = email
        self.phone = phone
        self.company = company
        self.note = note
        self.externalSourceID = externalSourceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from person: Person) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: person.id.uuidString,
            displayName: person.displayName,
            aliases: person.aliases,
            email: person.email,
            phone: person.phone,
            company: person.company,
            note: person.note,
            externalSourceID: person.externalSourceID,
            createdAt: formatter.string(from: person.createdAt),
            updatedAt: formatter.string(from: person.updatedAt)
        )
    }
}

/// Idempotent-upsert response for `people.create_idempotent`: the resulting person
/// plus whether it was newly created (vs. an update of an existing record matched by
/// `external_source_id`). People-shaped sibling to `IdempotentResponseDTO` (which wraps
/// a `TaskDTO`).
public struct PersonUpsertResponseDTO: Codable, Sendable, Equatable {
    public let person: PersonDTO
    public let wasCreated: Bool

    private enum CodingKeys: String, CodingKey {
        case person
        case wasCreated = "was_created"
    }

    public init(person: PersonDTO, wasCreated: Bool) {
        self.person = person
        self.wasCreated = wasCreated
    }
}

/// Aggregation response for `people.aggregate` ("everything about a person", spec §7):
/// raw graph endpoints grouped by kind, resolved by reverse-querying the `Link` graph.
/// IDs only — the MCP layer returns endpoints; a caller fetches the concrete rows via
/// the per-module tools (`tasks.get`, `note.get`, `meetings.*`).
public struct PersonAggregateDTO: Codable, Sendable, Equatable {
    public let personID: String
    /// Meetings the person attended (`.attendee` edges).
    public let meetings: [String]
    /// Tasks that MENTION the person (`.mentions` — never assignee, I1).
    public let tasks: [String]
    /// Notes that mention the person (`.mentions`).
    public let notes: [String]

    private enum CodingKeys: String, CodingKey {
        case personID = "person_id"
        case meetings
        case tasks
        case notes
    }

    public init(personID: String, meetings: [String], tasks: [String], notes: [String]) {
        self.personID = personID
        self.meetings = meetings
        self.tasks = tasks
        self.notes = notes
    }

    public init(personID: UUID, aggregate: PersonAggregate) {
        self.init(
            personID: personID.uuidString,
            meetings: aggregate.meetings.map(\.uuidString),
            tasks: aggregate.tasks.map(\.uuidString),
            notes: aggregate.notes.map(\.uuidString)
        )
    }
}
