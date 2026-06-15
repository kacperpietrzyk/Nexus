import Foundation
import SwiftData

/// CRUD + contact-linking for `Organization` (client/account). Bound to a single
/// `ModelContext`; never share across actors.
@MainActor
public final class OrganizationRepository {
    public let context: ModelContext
    public let now: () -> Date
    private let links: LinkRepository

    public init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
        self.links = LinkRepository(context: context)
    }

    @discardableResult
    public func create(name: String, sector: String? = nil) throws -> Organization {
        let stamp = now()
        let org = Organization(name: name, sector: sector)
        org.createdAt = stamp
        org.updatedAt = stamp
        context.insert(org)
        try context.save()
        return org
    }

    public func rename(_ org: Organization, to name: String) throws {
        org.name = name
        org.updatedAt = now()
        try context.save()
    }

    public func find(id: UUID) throws -> Organization? {
        try context.fetch(
            FetchDescriptor<Organization>(predicate: #Predicate { $0.id == id })
        ).first
    }

    /// All live (non-soft-deleted) organizations, sorted by name. Uses a fetch-all
    /// + in-memory filter to dodge the Release-mode `#Predicate` keypath trap on
    /// optional `deletedAt` (mirrors `PersonRepository.allActive()`).
    public func allActive() throws -> [Organization] {
        try context.fetch(FetchDescriptor<Organization>())
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func softDelete(_ org: Organization) throws {
        let stamp = now()
        org.deletedAt = stamp
        org.updatedAt = stamp
        try context.save()
    }

    /// Links a contact (`Person`) to this organization via the graph. Idempotent —
    /// a matching `(.person, personID) -mentions-> (.organization, org.id)` edge is
    /// created only if one does not already exist. (Typed RACI roles deferred.)
    @discardableResult
    public func linkPerson(_ personID: UUID, to org: Organization) throws -> Link {
        try links.findOrCreate(
            from: (.person, personID),
            to: (.organization, org.id),
            linkKind: .mentions
        )
    }
}
