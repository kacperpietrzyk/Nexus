import Foundation
import NexusCore
import SwiftData

// MARK: - people.create

/// Create a contact record (`Person`, spec §4.1). A person is never a task assignee
/// (invariant I1); it aggregates meetings/mentions purely through the graph.
public struct PeopleCreateTool: AgentTool {
    public let name = "people.create"
    public let description =
        "Creates a contact record (a Person). Only display_name is required; aliases, email, phone, "
        + "company, and a short note are optional. A Person is a contact record — never a task assignee. "
        + "Returns the created person."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "display_name": .string(description: "The person's display name."),
            "aliases": .array(
                items: .string(description: "Name/alias variant"),
                description: "Optional name variants used for dedup soft-matching."
            ),
            "email": .string(description: "Optional email address."),
            "phone": .string(description: "Optional phone number."),
            "company": .string(description: "Optional company (a plain field, not a separate entity)."),
            "note": .string(description: "Optional short free-form contact note."),
            "external_source_id": .string(
                description: "Optional stable import key (e.g. calendar-attendee:<email>) for idempotent "
                    + "imports; prefer people.create_idempotent when you have one."
            ),
        ],
        required: ["display_name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let displayName = try PeopleToolSupport.requiredString(args["display_name"], field: "display_name")
        let person = try context.personRepository.create(
            displayName: displayName,
            aliases: try PeopleToolSupport.aliases(args["aliases"]) ?? [],
            email: try PeopleToolSupport.optionalString(args["email"], field: "email"),
            phone: try PeopleToolSupport.optionalString(args["phone"], field: "phone"),
            company: try PeopleToolSupport.optionalString(args["company"], field: "company"),
            note: try PeopleToolSupport.optionalString(args["note"], field: "note"),
            externalSourceID: try PeopleToolSupport.optionalString(
                args["external_source_id"], field: "external_source_id"
            )
        )
        return try TasksToolJSON.encode(PersonDTO(from: person))
    }
}

// MARK: - people.create_idempotent

/// Idempotent upsert of a `Person` by `external_source_id` (spec §4.3 / §7): the same
/// `external_source_id` UPDATES the existing record rather than creating a duplicate.
/// Mutable fields are filled in only when non-empty (enrichment, never clobbering with
/// blanks); incoming aliases are unioned. Mirrors `tasks.create_idempotent`.
public struct PeopleCreateIdempotentTool: AgentTool {
    public let name = "people.create_idempotent"
    public let description =
        "Creates or updates one contact record by external_source_id without duplicating rows. "
        + "The same external_source_id updates the existing person (enriching empty fields, unioning "
        + "aliases). Returns the person and whether it was created."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "external_source_id": .string(
                description: "Stable import key, e.g. calendar-attendee:alice@example.com."
            ),
            "display_name": .string(description: "The person's display name."),
            "aliases": .array(
                items: .string(description: "Name/alias variant"),
                description: "Optional name variants (unioned into the existing record)."
            ),
            "email": .string(description: "Optional email address."),
            "phone": .string(description: "Optional phone number."),
            "company": .string(description: "Optional company."),
            "note": .string(description: "Optional short free-form contact note."),
        ],
        required: ["external_source_id", "display_name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let externalSourceID = try PeopleToolSupport.requiredString(
            args["external_source_id"], field: "external_source_id"
        )
        let displayName = try PeopleToolSupport.requiredString(args["display_name"], field: "display_name")

        let repo = context.personRepository
        let existedBefore = try PeopleToolSupport.liveExists(
            externalSourceID: externalSourceID, context: context
        )

        let person = try repo.upsert(
            externalSourceID: externalSourceID,
            displayName: displayName,
            aliases: try PeopleToolSupport.aliases(args["aliases"]) ?? [],
            email: try PeopleToolSupport.optionalString(args["email"], field: "email"),
            phone: try PeopleToolSupport.optionalString(args["phone"], field: "phone"),
            company: try PeopleToolSupport.optionalString(args["company"], field: "company"),
            note: try PeopleToolSupport.optionalString(args["note"], field: "note")
        )
        let response = PersonUpsertResponseDTO(person: PersonDTO(from: person), wasCreated: !existedBefore)
        return try TasksToolJSON.encode(response)
    }
}

// MARK: - people.update

/// Update a person's fields by id. Omitted fields are left untouched; an explicit JSON
/// `null` on email/phone/company/note clears that field (omit ≠ clear).
public struct PeopleUpdateTool: AgentTool {
    public let name = "people.update"
    public let description =
        "Updates a contact record by id. Omitted fields are left unchanged; pass null on "
        + "email/phone/company/note to clear them. Returns the updated person."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "id": .string(description: "Person UUID to update."),
            "display_name": .string(description: "New display name."),
            "aliases": .array(
                items: .string(description: "Name/alias variant"),
                description: "Replacement aliases (replaces the whole list)."
            ),
            "email": .string(description: "New email, or null to clear."),
            "phone": .string(description: "New phone, or null to clear."),
            "company": .string(description: "New company, or null to clear."),
            "note": .string(description: "New note, or null to clear."),
        ],
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try PeopleToolSupport.requiredUUID(args["id"], field: "id")
        let person = try PeopleToolSupport.livePerson(id: id, context: context)

        try context.personRepository.update(
            person,
            displayName: try PeopleToolSupport.optionalString(args["display_name"], field: "display_name"),
            aliases: try PeopleToolSupport.aliases(args["aliases"]),
            email: try PeopleToolSupport.nullableString(args["email"], field: "email"),
            phone: try PeopleToolSupport.nullableString(args["phone"], field: "phone"),
            company: try PeopleToolSupport.nullableString(args["company"], field: "company"),
            note: try PeopleToolSupport.nullableString(args["note"], field: "note")
        )
        return try TasksToolJSON.encode(PersonDTO(from: person))
    }
}

// MARK: - people.get

/// Fetch one contact record by id.
public struct PeopleGetTool: AgentTool {
    public let name = "people.get"
    public let description = "Fetches one contact record by id."
    public let inputSchema: JSONSchema = .object(
        properties: ["id": .string(description: "Person UUID to fetch.")],
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try PeopleToolSupport.requiredUUID(args["id"], field: "id")
        let person = try PeopleToolSupport.livePerson(id: id, context: context)
        return try TasksToolJSON.encode(PersonDTO(from: person))
    }
}

// MARK: - people.list

/// List all live contact records, sorted by display name.
public struct PeopleListTool: AgentTool {
    public let name = "people.list"
    public let description = "Lists all contact records (live, not soft-deleted), sorted by display name."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "limit": .integer(minimum: 1, maximum: 1000, description: "Max results (default 200).")
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let limit = AgentToolArgs.limit(args, default: 200, max: 1000)
        let people = try context.personRepository.allActive().prefix(limit)
        return try TasksToolJSON.encode(people.map { PersonDTO(from: $0) })
    }
}

// MARK: - people.search

/// Search contact records by a case/diacritic-insensitive substring over searchable
/// text (display name + aliases + company).
public struct PeopleSearchTool: AgentTool {
    public let name = "people.search"
    public let description =
        "Searches contact records by a case/diacritic-insensitive substring over the display name, "
        + "aliases, and company. Sorted by display name."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Substring to match in name, aliases, or company."),
            "limit": .integer(minimum: 1, maximum: 1000, description: "Max results (default 50)."),
        ],
        required: ["query"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let query = try PeopleToolSupport.requiredString(args["query"], field: "query")
        let limit = AgentToolArgs.limit(args, default: 50, max: 1000)
        let people = try PeopleToolSupport.fetch(context: context, searchableContains: query, limit: limit)
        return try TasksToolJSON.encode(people.map { PersonDTO(from: $0) })
    }
}

// MARK: - people.aggregate

/// "Everything about a person" (spec §7): meetings the person attended (`.attendee`)
/// plus tasks/notes that mention them (`.mentions`), resolved by reverse-querying the
/// `Link` graph. Returns raw endpoint IDs grouped by kind.
public struct PeopleAggregateTool: AgentTool {
    public let name = "people.aggregate"
    public let description =
        "Returns everything about a person: meeting IDs they attended plus task/note IDs that mention "
        + "them, resolved over the Link graph. Use tasks.get / note.get / meetings.* to fetch the rows."
    public let inputSchema: JSONSchema = .object(
        properties: ["id": .string(description: "Person UUID to aggregate.")],
        required: ["id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try PeopleToolSupport.requiredUUID(args["id"], field: "id")
        let person = try PeopleToolSupport.livePerson(id: id, context: context)
        let aggregate = try context.personRepository.aggregate(person)
        return try TasksToolJSON.encode(PersonAggregateDTO(personID: person.id, aggregate: aggregate))
    }
}

// MARK: - people.link

/// Link a person to a meeting / task / note. The edge label is DERIVED from
/// `object_kind` — `meeting → .attendee`, `task/note → .mentions` — there is NO
/// free-form link-kind argument. A `Person` is therefore never an assignee/owner; the
/// only `task ↔ person` edge this tool can ever emit is `.mentions` (invariant I1,
/// spec §5). Idempotent.
public struct PeopleLinkTool: AgentTool {
    public let name = "people.link"
    public let description =
        "Links a person to a meeting (as an attendee) or to a task/note (as a mention). The relationship "
        + "is fixed by object_kind — meetings get an attendee edge, tasks/notes get a mention edge. A "
        + "person is NEVER a task assignee. Idempotent."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "person_id": .string(description: "Person UUID."),
            "object_id": .string(description: "Meeting / task / note UUID."),
            "object_kind": .string(
                enumValues: ["meeting", "task", "note"],
                description: "meeting → attendee edge; task/note → mention edge. No other kind is allowed."
            ),
        ],
        required: ["person_id", "object_id", "object_kind"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let personID = try PeopleToolSupport.requiredUUID(args["person_id"], field: "person_id")
        let objectID = try PeopleToolSupport.requiredUUID(args["object_id"], field: "object_id")
        let sourceKind = try PeopleToolSupport.sourceKind(args["object_kind"])

        let repo = context.personRepository
        _ = try PeopleToolSupport.livePerson(id: personID, context: context)

        let link: Link
        switch sourceKind {
        case .meeting:
            link = try repo.linkAttendee(meetingID: objectID, personID: personID)
        case .task, .note:
            link = try repo.linkMention(source: sourceKind, sourceID: objectID, personID: personID)
        }

        return .object([
            "status": .string("ok"),
            "link_id": .string(link.id.uuidString),
            "link_kind": .string(link.linkKind.rawValue),
            "idempotency_key": .string(link.idempotencyKey),
        ])
    }
}

// MARK: - people.merge

/// Merge a duplicate person into a canonical one (dedup, spec §4.3 / §7). Atomically
/// repoints every graph edge from the duplicate onto the canonical record, unions
/// aliases/fields, and soft-deletes the duplicate (invariant I2 — no orphaned edges).
public struct PeopleMergeTool: AgentTool {
    public let name = "people.merge"
    public let description =
        "Merges a duplicate person (from_id) into a canonical one (into_id): repoints all graph edges, "
        + "unions aliases and fills empty fields, then soft-deletes the duplicate. Atomic. Returns the "
        + "surviving canonical person."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "into_id": .string(description: "Canonical Person UUID that survives the merge."),
            "from_id": .string(description: "Duplicate Person UUID that is merged away and soft-deleted."),
        ],
        required: ["into_id", "from_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let intoID = try PeopleToolSupport.requiredUUID(args["into_id"], field: "into_id")
        let fromID = try PeopleToolSupport.requiredUUID(args["from_id"], field: "from_id")
        let into = try PeopleToolSupport.livePerson(id: intoID, context: context)
        let from = try PeopleToolSupport.livePerson(id: fromID, context: context)

        do {
            try context.personRepository.mergePeople(into: into, from: from)
        } catch let error as PersonMergeError {
            switch error {
            case .cannotMergeIntoSelf:
                throw AgentError.validation("into_id and from_id must be different people.")
            case .sourceAlreadyDeleted:
                throw AgentError.conflict("from_id is already deleted.")
            }
        }
        return try TasksToolJSON.encode(PersonDTO(from: into))
    }
}
