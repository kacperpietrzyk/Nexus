import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("sections tools")
struct SectionsToolsTests {
    private struct Seed {
        let context: AgentContext
        let project: Project
        let repo: SectionRepository
    }

    @MainActor private func seed() async throws -> Seed {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let project = try context.projectRepository.create(name: "P", color: "azure", parentProjectID: nil)
        let repo = SectionRepository(context: context.modelContext.context, now: context.now)
        return Seed(context: context, project: project, repo: repo)
    }

    @Test("sections.list returns sections in a project")
    @MainActor
    func list() async throws {
        let seed = try await seed()
        _ = try seed.repo.create(projectID: seed.project.id, name: "A")
        _ = try seed.repo.create(projectID: seed.project.id, name: "B")
        let out = try await SectionsListTool().call(
            args: .object(["project_id": .string(seed.project.id.uuidString)]),
            context: seed.context
        )
        #expect(out["sections"]?.arrayValue?.count == 2)
    }

    @Test("sections.update renames")
    @MainActor
    func update() async throws {
        let seed = try await seed()
        let section = try seed.repo.create(projectID: seed.project.id, name: "Old")
        let out = try await SectionsUpdateTool().call(
            args: .object(["section_id": .string(section.id.uuidString), "name": .string("New")]),
            context: seed.context
        )
        #expect(out["name"]?.stringValue == "New")
    }

    @Test("sections.delete removes the section")
    @MainActor
    func delete() async throws {
        let seed = try await seed()
        let section = try seed.repo.create(projectID: seed.project.id, name: "Tmp")
        _ = try await SectionsDeleteTool().call(
            args: .object(["section_id": .string(section.id.uuidString)]),
            context: seed.context
        )
        #expect(try seed.repo.sections(in: seed.project.id).isEmpty)
    }

    @Test("sections.delete reassigns its tasks to the destination section")
    @MainActor
    func deleteWithReassign() async throws {
        let seed = try await seed()
        let source = try seed.repo.create(projectID: seed.project.id, name: "Src")
        let destination = try seed.repo.create(projectID: seed.project.id, name: "Dst")
        let modelContext = seed.context.modelContext.context
        let task = TaskItem(title: "Work", projectID: seed.project.id, sectionID: source.id)
        modelContext.insert(task)
        try modelContext.save()

        _ = try await SectionsDeleteTool().call(
            args: .object([
                "section_id": .string(source.id.uuidString),
                "reassign_to_section_id": .string(destination.id.uuidString),
            ]),
            context: seed.context
        )

        #expect(try seed.repo.sections(in: seed.project.id).map(\.id) == [destination.id])
        #expect(task.sectionID == destination.id)
    }

    @Test("sections.reorder moves a section between two siblings")
    @MainActor
    func reorder() async throws {
        let seed = try await seed()
        let first = try seed.repo.create(projectID: seed.project.id, name: "First")
        let second = try seed.repo.create(projectID: seed.project.id, name: "Second")
        let third = try seed.repo.create(projectID: seed.project.id, name: "Third")
        // Move `third` to sit between `first` and `second`.
        let out = try await SectionsReorderTool().call(
            args: .object([
                "section_id": .string(third.id.uuidString),
                "after_section_id": .string(first.id.uuidString),
                "before_section_id": .string(second.id.uuidString),
            ]),
            context: seed.context
        )
        #expect(out["id"]?.stringValue == third.id.uuidString)
        let ordered = try seed.repo.sections(in: seed.project.id).map(\.id)
        #expect(ordered == [first.id, third.id, second.id])
    }
}
