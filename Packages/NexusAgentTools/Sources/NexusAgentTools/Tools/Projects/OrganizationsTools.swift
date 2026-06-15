import Foundation
import NexusCore
import SwiftData

// MARK: - organizations.create

/// Create an Organization, or return the existing one when `external_source_id` matches
/// (idempotent import). Returns org fields + `was_created` at the top level.
public struct OrganizationsCreateTool: AgentTool {
    public let name = "organizations.create"
    public let description =
        "Creates a client/account Organization, or returns the existing one when "
        + "external_source_id matches (idempotent import). Returns the org fields and "
        + "was_created (false when an existing record was matched)."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "name": .string(description: "Organization name."),
            "sector": .string(description: "Optional sector/industry."),
            "external_source_id": .string(
                description: "Optional idempotency key; a repeat call with the same value "
                    + "updates instead of duplicating."
            ),
        ],
        required: ["name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let sector = try ProjectsToolSupport.optionalTrimmedString(args["sector"], field: "sector")
        let externalID = try ProjectsToolSupport.optionalTrimmedString(
            args["external_source_id"], field: "external_source_id"
        )

        let existing: Organization? = try externalID.flatMap { id in
            try OrganizationsToolSupport.existing(externalSourceID: id, context: context)
        }
        if let existing {
            try context.organizationRepository.rename(existing, to: name)
            if let sector {
                existing.sector = sector
                existing.updatedAt = context.now()
            }
            try context.modelContext.context.save()
            return try flatResponse(from: existing, wasCreated: false)
        }

        let org = try context.organizationRepository.create(name: name, sector: sector)
        if let externalID {
            org.externalSourceID = externalID
            try context.modelContext.context.save()
        }
        return try flatResponse(from: org, wasCreated: true)
    }

    private func flatResponse(from org: Organization, wasCreated: Bool) throws -> JSONValue {
        var obj = (try TasksToolJSON.encode(OrganizationDTO(from: org))).objectValue ?? [:]
        obj["was_created"] = .bool(wasCreated)
        return .object(obj)
    }
}

// MARK: - organizations.list

/// List all live (non-soft-deleted) organizations, sorted by name.
public struct OrganizationsListTool: AgentTool {
    public let name = "organizations.list"
    public let description =
        "Lists all active (non-deleted) organizations sorted by name. Returns an array "
        + "under the key 'organizations'."
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
        let orgs = try context.organizationRepository.allActive().prefix(limit)
        let dtos = try orgs.map { try TasksToolJSON.encode(OrganizationDTO(from: $0)) }
        return .object(["organizations": .array(dtos)])
    }
}

// MARK: - organizations.get

/// Fetch one organization by id.
public struct OrganizationsGetTool: AgentTool {
    public let name = "organizations.get"
    public let description = "Fetches one organization by id."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "organization_id": .string(description: "Organization UUID to fetch.")
        ],
        required: ["organization_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try OrganizationsToolSupport.requiredOrganizationID(args)
        let org = try OrganizationsToolSupport.liveOrganization(id: id, context: context)
        return try TasksToolJSON.encode(OrganizationDTO(from: org))
    }
}

// MARK: - organizations.update

/// Update an organization's mutable fields. Omitted fields are left untouched.
public struct OrganizationsUpdateTool: AgentTool {
    public let name = "organizations.update"
    public let description =
        "Updates an organization's name, sector, or note. Omitted fields are left unchanged. "
        + "Returns the updated organization."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "organization_id": .string(description: "Organization UUID to update."),
            "name": .string(description: "New name."),
            "sector": .string(description: "New sector, or null to clear."),
            "note": .string(description: "New note, or null to clear."),
        ],
        required: ["organization_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try OrganizationsToolSupport.requiredOrganizationID(args)
        let org = try OrganizationsToolSupport.liveOrganization(id: id, context: context)

        if let newName = try ProjectsToolSupport.optionalTrimmedString(args["name"], field: "name") {
            try context.organizationRepository.rename(org, to: newName)
        }

        let sector = args["sector"]
        if let sector {
            if case .null = sector {
                org.sector = nil
            } else if let text = sector.stringValue {
                org.sector = text
            } else {
                throw AgentError.validation("sector must be a string or null")
            }
            org.updatedAt = context.now()
        }

        let note = args["note"]
        if let note {
            if case .null = note {
                org.note = nil
            } else if let text = note.stringValue {
                org.note = text
            } else {
                throw AgentError.validation("note must be a string or null")
            }
            org.updatedAt = context.now()
        }

        try context.modelContext.context.save()
        return try TasksToolJSON.encode(OrganizationDTO(from: org))
    }
}

// MARK: - organizations.link_person

/// Link a Person to an Organization via the polymorphic graph. Idempotent.
public struct OrganizationsLinkPersonTool: AgentTool {
    public let name = "organizations.link_person"
    public let description =
        "Links a contact (Person) to an Organization via the graph "
        + "(.person -mentions-> .organization). Idempotent — calling twice creates only one edge."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "organization_id": .string(description: "Organization UUID."),
            "person_id": .string(description: "Person UUID to link to the organization."),
        ],
        required: ["organization_id", "person_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let orgID = try OrganizationsToolSupport.requiredOrganizationID(args)
        let personID = try OrganizationsToolSupport.requiredPersonID(args)

        let org = try OrganizationsToolSupport.liveOrganization(id: orgID, context: context)
        _ = try PeopleToolSupport.livePerson(id: personID, context: context)

        try context.organizationRepository.linkPerson(personID, to: org)
        return .object(["ok": .bool(true)])
    }
}
