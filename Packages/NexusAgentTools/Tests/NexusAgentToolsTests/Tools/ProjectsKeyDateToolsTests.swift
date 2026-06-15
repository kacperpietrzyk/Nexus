import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("Project key-date tools")
struct ProjectsKeyDateToolsTests {
    @MainActor
    @Test("set, list (date-sorted), and delete a key date")
    func lifecycle() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "AKMF", type: .implementation)
        let registry = ToolRegistry(tools: CoreTaskTools.all())
        let set = try #require(registry.tool(named: "projects.set_key_date"))
        _ = try await set.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "anchor_key": .string("PO"),
                "label": .string("Protokół Odbioru"),
                "date": .string("2026-07-29T00:00:00Z"),
                "is_contractual": .bool(true),
            ]),
            context: fixture.context
        )
        _ = try await set.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "anchor_key": .string("T0"),
                "label": .string("Umowa"),
                "date": .string("2026-06-02T00:00:00Z"),
            ]),
            context: fixture.context
        )

        let list = try await #require(registry.tool(named: "projects.list_key_dates")).call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: fixture.context
        )
        let keys = list["key_dates"]?.arrayValue?.compactMap { $0["anchor_key"]?.stringValue }
        #expect(keys == ["T0", "PO"])

        _ = try await #require(registry.tool(named: "projects.delete_key_date")).call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "anchor_key": .string("T0"),
            ]),
            context: fixture.context
        )
        let after = try fixture.context.projectKeyDateRepository.list(projectID: project.id)
        #expect(after.map(\.anchorKey) == ["PO"])
    }
}
