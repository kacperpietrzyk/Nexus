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
}
