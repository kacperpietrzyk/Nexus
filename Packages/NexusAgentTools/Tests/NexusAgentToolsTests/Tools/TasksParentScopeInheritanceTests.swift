import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Tasks parent-scope inheritance")
struct TasksParentScopeInheritanceTests {
    @MainActor
    @Test("tasks.create parent_id inherits parent project and section")
    func createInheritsParentProjectAndSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let scopedParent = try makeScopedParent(in: fixture.repo)

        let dto = try await create(
            args: .object([
                "title": .string("child"),
                "parent_id": .string(scopedParent.parent.id.uuidString),
            ]),
            context: fixture.context
        )

        let child = try #require(
            try fixture.repo.context.fetch(FetchDescriptor<TaskItem>()).first {
                $0.id != scopedParent.parent.id
            })
        #expect(dto.parentID == scopedParent.parent.id.uuidString)
        #expect(dto.projectID == scopedParent.project.id.uuidString)
        #expect(dto.sectionID == scopedParent.section.id.uuidString)
        #expect(child.projectID == scopedParent.project.id)
        #expect(child.sectionID == scopedParent.section.id)
    }

    @MainActor
    @Test("tasks.update parent_id inherits parent project and section")
    func updateInheritsParentProjectAndSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let scopedParent = try makeScopedParent(in: fixture.repo)
        let oldProject = Project(name: "Old Project")
        let oldSection = Section(projectID: oldProject.id, name: "Inbox")
        fixture.repo.context.insert(oldProject)
        fixture.repo.context.insert(oldSection)
        try fixture.repo.context.save()
        let child = TaskItem(title: "Child", projectID: oldProject.id, sectionID: oldSection.id)
        try fixture.repo.insert(child)

        let dto = try await update(
            args: .object([
                "task_id": .string(child.id.uuidString),
                "patch": .object(["parent_id": .string(scopedParent.parent.id.uuidString)]),
            ]),
            context: fixture.context
        )

        #expect(dto.parentID == scopedParent.parent.id.uuidString)
        #expect(dto.projectID == scopedParent.project.id.uuidString)
        #expect(dto.sectionID == scopedParent.section.id.uuidString)
        #expect(child.projectID == scopedParent.project.id)
        #expect(child.sectionID == scopedParent.section.id)
    }

    @MainActor
    @Test("tasks.create_idempotent create parent_id inherits parent project and section")
    func idempotentCreateInheritsParentProjectAndSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let scopedParent = try makeScopedParent(in: fixture.repo)

        let response = try await createIdempotent(
            args: .object([
                "external_source_id": .string("todoist:parent-only-create"),
                "title": .string("child"),
                "parent_id": .string(scopedParent.parent.id.uuidString),
            ]),
            context: fixture.context
        )

        let child = try #require(
            try fixture.repo.context.fetch(FetchDescriptor<TaskItem>()).first {
                $0.id != scopedParent.parent.id
            })
        #expect(response.wasCreated)
        #expect(response.task.parentID == scopedParent.parent.id.uuidString)
        #expect(response.task.projectID == scopedParent.project.id.uuidString)
        #expect(response.task.sectionID == scopedParent.section.id.uuidString)
        #expect(child.projectID == scopedParent.project.id)
        #expect(child.sectionID == scopedParent.section.id)
    }

    @MainActor
    @Test("tasks.create_idempotent rerun parent_id inherits parent project and section")
    func idempotentRerunInheritsParentProjectAndSection() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let scopedParent = try makeScopedParent(in: fixture.repo)
        let oldProject = Project(name: "Old Project")
        let oldSection = Section(projectID: oldProject.id, name: "Inbox")
        fixture.repo.context.insert(oldProject)
        fixture.repo.context.insert(oldSection)
        try fixture.repo.context.save()

        _ = try await createIdempotent(
            args: .object([
                "external_source_id": .string("todoist:parent-only-rerun"),
                "title": .string("child"),
                "project_id": .string(oldProject.id.uuidString),
                "section_id": .string(oldSection.id.uuidString),
            ]),
            context: fixture.context
        )

        let response = try await createIdempotent(
            args: .object([
                "external_source_id": .string("todoist:parent-only-rerun"),
                "title": .string("child"),
                "parent_id": .string(scopedParent.parent.id.uuidString),
            ]),
            context: fixture.context
        )

        let child = try #require(
            try fixture.repo.context.fetch(FetchDescriptor<TaskItem>()).first {
                $0.externalSourceID == "todoist:parent-only-rerun"
            })
        #expect(!response.wasCreated)
        #expect(response.task.parentID == scopedParent.parent.id.uuidString)
        #expect(response.task.projectID == scopedParent.project.id.uuidString)
        #expect(response.task.sectionID == scopedParent.section.id.uuidString)
        #expect(child.projectID == scopedParent.project.id)
        #expect(child.sectionID == scopedParent.section.id)
    }

    @MainActor
    private struct ScopedParent {
        let parent: TaskItem
        let project: Project
        let section: Section
    }

    @MainActor
    private func makeScopedParent(in repo: TaskItemRepository) throws -> ScopedParent {
        let project = Project(name: "Parent Project")
        let section = Section(projectID: project.id, name: "Doing")
        repo.context.insert(project)
        repo.context.insert(section)
        try repo.context.save()
        let parent = TaskItem(title: "Parent", projectID: project.id, sectionID: section.id)
        try repo.insert(parent)
        return ScopedParent(parent: parent, project: project, section: section)
    }

    @MainActor
    private func create(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksCreateTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }

    @MainActor
    private func update(args: JSONValue, context: AgentContext) async throws -> TaskDTO {
        let result = try await TasksUpdateTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskDTO.self, from: data)
    }

    @MainActor
    private func createIdempotent(
        args: JSONValue,
        context: AgentContext
    ) async throws -> IdempotentResponseDTO {
        let result = try await TasksCreateIdempotentTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(IdempotentResponseDTO.self, from: data)
    }
}
