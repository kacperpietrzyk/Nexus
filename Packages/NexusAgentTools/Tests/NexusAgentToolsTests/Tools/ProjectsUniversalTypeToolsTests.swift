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
        // client_id is now validated as a live Organization FK (parity with parent_project_id),
        // so seed the organization the create references.
        let clientID = try fixture.context.organizationRepository.create(name: "AKMF Client").id
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

    @MainActor
    @Test("projects.update sets type/vendor and a custom field")
    func updateSetsFields() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "P")
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.update"))
        let result = try await tool.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "type": .string("sales"),
                "vendor": .string("CrowdStrike Falcon"),
                "custom_field_key": .string("competitor"),
                "custom_field_value": .string("Apius"),
            ]),
            context: fixture.context
        )
        #expect(result["type"]?.stringValue == "sales")
        #expect(result["vendor"]?.stringValue == "CrowdStrike Falcon")
        #expect(result["custom_fields"]?["competitor"]?.stringValue == "Apius")
    }

    @MainActor
    @Test("projects.update with null custom_field_value removes the key")
    func updateRemovesCustomField() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "P")
        try fixture.context.projectRepository.setCustomField(key: "k", value: "v", on: project)
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.update"))
        let result = try await tool.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "custom_field_key": .string("k"),
                "custom_field_value": .null,
            ]),
            context: fixture.context
        )
        #expect(result["custom_fields"]?["k"] == nil)
    }

    @MainActor
    @Test("projects.update rejects a malformed client_id instead of silently clearing it")
    func updateRejectsBadClientID() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let clientID = UUID()
        let project = try fixture.context.projectRepository.create(name: "P")
        try fixture.context.projectRepository.setClient(clientID, on: project)
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.update"))
        await #expect(throws: AgentError.self) {
            _ = try await tool.call(
                args: .object([
                    "project_id": .string(project.id.uuidString),
                    "client_id": .string("not-a-uuid"),
                ]),
                context: fixture.context
            )
        }
        // The bad input must not have wiped the existing association.
        let reloaded = try #require(try fixture.context.projectRepository.find(id: project.id))
        #expect(reloaded.clientID == clientID)
    }

    @MainActor
    @Test("projects.update with an empty client_id clears the association")
    func updateClearsClientWithEmptyString() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "P")
        try fixture.context.projectRepository.setClient(UUID(), on: project)
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.update"))
        let result = try await tool.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "client_id": .string(""),
            ]),
            context: fixture.context
        )
        #expect(result["client_id"] == nil || result["client_id"] == .null)
    }

    @MainActor
    @Test("projects.set_stage sets stage and syncs status")
    func setStageSyncsStatus() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "Sale", type: .sales)
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.set_stage"))
        let result = try await tool.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "stage": .string("won"),
            ]),
            context: fixture.context
        )
        #expect(result["stage"]?.stringValue == "won")
        #expect(result["status"]?.stringValue == "completed")
    }

    @MainActor
    @Test("projects.set_stage rejects a stage outside the type preset")
    func setStageRejectsForeign() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "Sale", type: .sales)
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.set_stage"))
        await #expect(throws: AgentError.self) {
            _ = try await tool.call(
                args: .object([
                    "project_id": .string(project.id.uuidString),
                    "stage": .string("kickoff"),
                ]),
                context: fixture.context
            )
        }
    }
}
