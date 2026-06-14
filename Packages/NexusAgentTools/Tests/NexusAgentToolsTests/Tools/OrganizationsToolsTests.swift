import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Organizations tools")
struct OrganizationsToolsTests {
    @MainActor
    @Test("organizations.create then list and get")
    func createListGet() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let registry = ToolRegistry(tools: CoreTaskTools.all())
        let create = try #require(registry.tool(named: "organizations.create"))
        let created = try await create.call(
            args: .object([
                "name": .string("AKMF"), "sector": .string("Skarb Państwa"),
            ]),
            context: fixture.context
        )
        let id = try #require(created["id"]?.stringValue)

        let listTool = try #require(registry.tool(named: "organizations.list"))
        let list = try await listTool.call(args: .object([:]), context: fixture.context)
        #expect(list["organizations"]?.arrayValue?.count == 1)

        let getTool = try #require(registry.tool(named: "organizations.get"))
        let get = try await getTool.call(
            args: .object(["organization_id": .string(id)]),
            context: fixture.context
        )
        #expect(get["name"]?.stringValue == "AKMF")
        #expect(get["sector"]?.stringValue == "Skarb Państwa")
    }

    @MainActor
    @Test("organizations.create is idempotent on external_source_id")
    func createIdempotent() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let registry = ToolRegistry(tools: CoreTaskTools.all())
        let create = try #require(registry.tool(named: "organizations.create"))
        let a = try await create.call(
            args: .object(["name": .string("AKMF"), "external_source_id": .string("ext:akmf")]),
            context: fixture.context
        )
        let b = try await create.call(
            args: .object(["name": .string("AKMF renamed"), "external_source_id": .string("ext:akmf")]),
            context: fixture.context
        )
        #expect(a["id"]?.stringValue == b["id"]?.stringValue)
        #expect(b["was_created"]?.boolValue == false)
        #expect(b["name"]?.stringValue == "AKMF renamed")
        let all = try fixture.context.organizationRepository.allActive()
        #expect(all.count == 1)
    }

    @MainActor
    @Test("organizations.update: omit keeps, null clears, value sets")
    func updateOmitNullSet() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let registry = ToolRegistry(tools: CoreTaskTools.all())
        let org = try fixture.context.organizationRepository.create(name: "AKMF", sector: "Skarb Państwa")
        let update = try #require(registry.tool(named: "organizations.update"))
        let get = try #require(registry.tool(named: "organizations.get"))

        // Update only the name; sector (omitted) must survive.
        _ = try await update.call(
            args: .object([
                "organization_id": .string(org.id.uuidString),
                "name": .string("AKMF S.A."),
            ]),
            context: fixture.context
        )
        let afterName = try await get.call(
            args: .object(["organization_id": .string(org.id.uuidString)]),
            context: fixture.context
        )
        #expect(afterName["name"]?.stringValue == "AKMF S.A.")
        #expect(afterName["sector"]?.stringValue == "Skarb Państwa")

        // Set sector to a new value.
        _ = try await update.call(
            args: .object([
                "organization_id": .string(org.id.uuidString),
                "sector": .string("Energetyka"),
            ]),
            context: fixture.context
        )
        let afterSet = try await get.call(
            args: .object(["organization_id": .string(org.id.uuidString)]),
            context: fixture.context
        )
        #expect(afterSet["sector"]?.stringValue == "Energetyka")

        // Explicit null clears sector.
        _ = try await update.call(
            args: .object([
                "organization_id": .string(org.id.uuidString),
                "sector": .null,
            ]),
            context: fixture.context
        )
        let afterClear = try await get.call(
            args: .object(["organization_id": .string(org.id.uuidString)]),
            context: fixture.context
        )
        #expect(afterClear["sector"]?.stringValue == nil)
        #expect(afterClear["name"]?.stringValue == "AKMF S.A.")
    }

    @MainActor
    @Test("organizations.link_person links a contact idempotently")
    func linkPerson() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let org = try fixture.context.organizationRepository.create(name: "AKMF")
        let person = try fixture.context.personRepository.create(displayName: "Remigiusz Rybacki")
        let registry = ToolRegistry(tools: CoreTaskTools.all())
        let tool = try #require(registry.tool(named: "organizations.link_person"))
        let linkArgs = JSONValue.object([
            "organization_id": .string(org.id.uuidString),
            "person_id": .string(person.id.uuidString),
        ])
        _ = try await tool.call(args: linkArgs, context: fixture.context)
        _ = try await tool.call(args: linkArgs, context: fixture.context)
        let edges = try fixture.context.modelContext.context.fetch(FetchDescriptor<Link>()).filter {
            $0.linkKind == .mentions && $0.fromKind == .person && $0.toKind == .organization
        }
        #expect(edges.count == 1)
    }
}
