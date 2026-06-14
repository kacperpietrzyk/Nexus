import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Projects universal-type tool surface")
struct ProjectsUniversalTypeToolsTests {
    @MainActor
    @Test("ProjectDTO surfaces type/stage/client/vendor/custom_fields")
    func dtoSurfacesNewFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let repo = fixture.context.projectRepository
        let project = try repo.create(name: "AKMF", type: .implementation)
        let clientID = UUID()
        try repo.setStage(.deliveryDocs, on: project)
        try repo.setClient(clientID, on: project)
        try repo.setVendor("Proofpoint DLP", on: project)
        try repo.setCustomField(key: "dealValue", value: "690891 PLN", on: project)

        let json = try TasksToolJSON.encode(ProjectDTO(from: project))
        #expect(json["type"]?.stringValue == "implementation")
        #expect(json["stage"]?.stringValue == "deliveryDocs")
        #expect(json["client_id"]?.stringValue == clientID.uuidString)
        #expect(json["vendor"]?.stringValue == "Proofpoint DLP")
        #expect(json["custom_fields"]?["dealValue"]?.stringValue == "690891 PLN")
    }

    @MainActor
    @Test("projects.create accepts type/client_id/vendor")
    func createAcceptsTypeFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.create"))
        let clientID = UUID()
        let result = try await tool.call(
            args: .object([
                "name": .string("AKMF"),
                "type": .string("implementation"),
                "client_id": .string(clientID.uuidString),
                "vendor": .string("Proofpoint DLP"),
            ]),
            context: fixture.context
        )
        #expect(result["type"]?.stringValue == "implementation")
        #expect(result["client_id"]?.stringValue == clientID.uuidString)
        #expect(result["vendor"]?.stringValue == "Proofpoint DLP")
    }

    @MainActor
    @Test("projects.create rejects an invalid type")
    func createRejectsBadType() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.create"))
        await #expect(throws: AgentError.self) {
            _ = try await tool.call(args: .object(["name": .string("X"), "type": .string("bogus")]), context: fixture.context)
        }
    }
}
