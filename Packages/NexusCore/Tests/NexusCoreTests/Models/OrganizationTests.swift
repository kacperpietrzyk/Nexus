import Foundation
import SwiftData
import Testing
@testable import NexusCore

@Suite("Organization")
struct OrganizationTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Organization.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("organization persists and round-trips")
    func roundTrip() throws {
        let context = try makeContext()
        let org = Organization(name: "AKMF", sector: "Skarb Państwa")
        context.insert(org)
        try context.save()

        let id = org.id
        let fetched = try context.fetch(
            FetchDescriptor<Organization>(predicate: #Predicate { $0.id == id })
        ).first
        #expect(fetched?.name == "AKMF")
        #expect(fetched?.sector == "Skarb Państwa")
        #expect(fetched?.kind == .organization)
        #expect(fetched?.deletedAt == nil)
    }

    @Test("searchableText includes name, aliases, sector; title bridges name")
    func searchable() {
        let org = Organization(name: "Volkswagen Poznań", aliases: ["VW", "VWP"], sector: "automotive")
        #expect(org.title == "Volkswagen Poznań")
        #expect(org.searchableText.contains("VWP"))
        #expect(org.searchableText.contains("automotive"))
    }

    @Test("ItemKind.organization has a stable raw value and display name")
    func itemKind() {
        #expect(ItemKind.organization.rawValue == "organization")
        #expect(ItemKind.organization.displayName == "Organization")
    }
}
