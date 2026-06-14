import Foundation
import NexusCore
import SwiftData

enum OrganizationsToolSupport {
    /// Resolves a live (non-soft-deleted) `Organization` by UUID, throwing `notFound`.
    @MainActor
    static func liveOrganization(id: UUID, context: AgentContext) throws -> Organization {
        guard let org = try context.organizationRepository.find(id: id), org.deletedAt == nil else {
            throw AgentError.notFound("Organization not found: \(id.uuidString)")
        }
        return org
    }

    /// Returns the first live organization matching `externalSourceID`, or nil.
    @MainActor
    static func existing(externalSourceID: String, context: AgentContext) throws -> Organization? {
        let descriptor = FetchDescriptor<Organization>(
            predicate: #Predicate { $0.externalSourceID == externalSourceID }
        )
        return try context.modelContext.context.fetch(descriptor).first { $0.deletedAt == nil }
    }

    /// Parses a required UUID from `organization_id`.
    static func requiredOrganizationID(_ args: JSONValue) throws -> UUID {
        guard let text = args["organization_id"]?.stringValue, let id = UUID(uuidString: text) else {
            throw AgentError.validation("organization_id must be a valid UUID")
        }
        return id
    }

    /// Parses a required UUID from `person_id`.
    static func requiredPersonID(_ args: JSONValue) throws -> UUID {
        guard let text = args["person_id"]?.stringValue, let id = UUID(uuidString: text) else {
            throw AgentError.validation("person_id must be a valid UUID")
        }
        return id
    }
}

// MARK: - OrganizationDTO

/// Wire format for an `Organization` exposed via MCP. snake_case keys per MCP convention.
struct OrganizationDTO: Encodable {
    let id: String
    let name: String
    let sector: String?
    let aliases: [String]
    let externalSourceID: String?
    let note: String?
    let createdAt: String
    let updatedAt: String

    init(from org: Organization) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = org.id.uuidString
        self.name = org.name
        self.sector = org.sector
        self.aliases = org.aliases
        self.externalSourceID = org.externalSourceID
        self.note = org.note
        self.createdAt = formatter.string(from: org.createdAt)
        self.updatedAt = formatter.string(from: org.updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sector, aliases, note
        case externalSourceID = "external_source_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
