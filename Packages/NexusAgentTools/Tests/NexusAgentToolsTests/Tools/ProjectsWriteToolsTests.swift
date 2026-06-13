import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("projects write")
struct ProjectsWriteToolsTests {
    @Test("projects.list returns active projects")
    @MainActor
    func listProjects() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        _ = try context.projectRepository.create(name: "Alpha", color: "azure", parentProjectID: nil)
        _ = try context.projectRepository.create(name: "Beta", color: "azure", parentProjectID: nil)
        let out = try await ProjectsListTool().call(args: .object([:]), context: context)
        let names = out["projects"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(names?.sorted() == ["Alpha", "Beta"])
    }

    @Test("projects.update renames")
    @MainActor
    func renameProject() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let project = try context.projectRepository.create(name: "Old", color: "azure", parentProjectID: nil)
        let out = try await ProjectsUpdateTool().call(
            args: .object(["project_id": .string(project.id.uuidString), "name": .string("New")]),
            context: context
        )
        #expect(out["name"]?.stringValue == "New")
    }

    @Test("projects.archive then projects.delete remove from active list")
    @MainActor
    func archiveAndDelete() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let project = try context.projectRepository.create(name: "Tmp", color: "azure", parentProjectID: nil)
        _ = try await ProjectsArchiveTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: context
        )
        _ = try await ProjectsDeleteTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: context
        )
        // `find(id:)` does not filter soft-deleted rows, so assert the soft-delete
        // contract (`deletedAt` set) plus the operational "removed from active"
        // signal: the live-resolution path the tools use now throws `notFound`.
        #expect(try context.projectRepository.find(id: project.id)?.deletedAt != nil)
        await #expect(throws: AgentError.self) {
            _ = try await ProjectsGetTool().call(
                args: .object(["project_id": .string(project.id.uuidString)]),
                context: context
            )
        }
    }

    @Test("projects.get includes sections")
    @MainActor
    func getIncludesSections() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let project = try context.projectRepository.create(name: "Withsec", color: "azure", parentProjectID: nil)
        let sections = SectionRepository(context: context.modelContext.context, now: context.now)
        _ = try sections.create(projectID: project.id, name: "Backlog")
        let out = try await ProjectsGetTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: context
        )
        let secNames = out["sections"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(secNames == ["Backlog"])
    }
}
