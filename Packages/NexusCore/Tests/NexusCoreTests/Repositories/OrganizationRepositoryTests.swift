import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("OrganizationRepository")
struct OrganizationRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Organization.self, Person.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("create + find + allActive excludes soft-deleted")
    func crud() throws {
        let context = try makeContext()
        let repo = OrganizationRepository(context: context)

        let akmf = try repo.create(name: "AKMF", sector: "Skarb Państwa")
        let vw = try repo.create(name: "Volkswagen Poznań")
        try repo.softDelete(vw)

        #expect(try repo.find(id: akmf.id)?.name == "AKMF")
        let active = try repo.allActive()
        #expect(active.map(\.name) == ["AKMF"])
    }

    @MainActor
    @Test("linkPerson creates a single Person→Organization edge, idempotently")
    func linkPerson() throws {
        let context = try makeContext()
        let repo = OrganizationRepository(context: context)
        let org = try repo.create(name: "AKMF")
        let personID = UUID()

        try repo.linkPerson(personID, to: org)
        try repo.linkPerson(personID, to: org)

        let edges = try context.fetch(FetchDescriptor<Link>()).filter {
            $0.linkKind == .mentions && $0.fromKind == .person && $0.toKind == .organization
        }
        #expect(edges.count == 1)
        #expect(edges.first?.fromID == personID)
        #expect(edges.first?.toID == org.id)
    }
}
