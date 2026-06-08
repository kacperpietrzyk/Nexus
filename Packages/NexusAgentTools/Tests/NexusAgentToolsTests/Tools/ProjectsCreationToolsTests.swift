import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Projects creation tools")
struct ProjectsCreationToolsTests {
    @MainActor
    @Test("projects.create is registered and creates a project")
    func projectsCreateRegistersAndCreatesProject() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.create"))

        let result = try await tool.call(
            args: .object([
                "name": .string("CyberLab"),
                "glyph": .string("folder"),
            ]),
            context: fixture.context
        )

        let idText = try #require(result["id"]?.stringValue)
        let id = try #require(UUID(uuidString: idText))
        let stored = try #require(try fixture.context.projectRepository.find(id: id))
        #expect(result["name"]?.stringValue == "CyberLab")
        #expect(result["glyph"]?.stringValue == "folder")
        #expect(stored.name == "CyberLab")
        #expect(stored.color == "folder")
    }

    @MainActor
    @Test("projects.sections.create is registered and creates a section in a project")
    func sectionsCreateRegistersAndCreatesSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let project = try fixture.context.projectRepository.create(name: "CyberLab")
        let tool = try #require(ToolRegistry(tools: CoreTaskTools.all()).tool(named: "projects.sections.create"))

        let result = try await tool.call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "name": .string("Doing"),
            ]),
            context: fixture.context
        )

        let idText = try #require(result["id"]?.stringValue)
        let id = try #require(UUID(uuidString: idText))
        let sections = try SectionRepository(context: fixture.repo.context).sections(in: project.id)
        let stored = try #require(sections.first { $0.id == id })
        #expect(result["project_id"]?.stringValue == project.id.uuidString)
        #expect(result["name"]?.stringValue == "Doing")
        #expect(stored.projectID == project.id)
        #expect(stored.name == "Doing")
    }
}
