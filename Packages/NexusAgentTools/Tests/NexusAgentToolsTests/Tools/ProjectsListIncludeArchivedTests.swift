import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("projects.list include_archived + tasks.orphaned")
struct ProjectsListIncludeArchivedTests {

    // MARK: - projects.list include_archived

    @MainActor
    @Test("archived project is hidden by default")
    func archivedProjectHiddenByDefault() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let active = Project(name: "Active")
        let archived = Project(name: "Archived")
        ctx.modelContext.context.insert(active)
        ctx.modelContext.context.insert(archived)
        try ctx.modelContext.context.save()
        try ctx.projectRepository.archive(archived)

        let result = try await ProjectsListTool().call(args: .object([:]), context: ctx)
        let names = try projectNames(from: result)

        #expect(names == ["Active"])
        #expect(!names.contains("Archived"))
    }

    @MainActor
    @Test("archived project surfaces with include_archived:true")
    func archivedProjectSurfacesWithFlag() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let active = Project(name: "Active")
        let archived = Project(name: "Archived")
        ctx.modelContext.context.insert(active)
        ctx.modelContext.context.insert(archived)
        try ctx.modelContext.context.save()
        try ctx.projectRepository.archive(archived)

        let result = try await ProjectsListTool().call(
            args: .object(["include_archived": .bool(true)]),
            context: ctx
        )
        let names = try projectNames(from: result)

        #expect(names.contains("Active"))
        #expect(names.contains("Archived"))
        #expect(names.count == 2)
    }

    @MainActor
    @Test("soft-deleted project never appears even with include_archived:true")
    func deletedProjectNeverSurfaces() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let live = Project(name: "Live")
        let deleted = Project(name: "Deleted")
        ctx.modelContext.context.insert(live)
        ctx.modelContext.context.insert(deleted)
        try ctx.modelContext.context.save()
        try ctx.projectRepository.softDelete(deleted)

        let result = try await ProjectsListTool().call(
            args: .object(["include_archived": .bool(true)]),
            context: ctx
        )
        let names = try projectNames(from: result)

        #expect(names == ["Live"])
        #expect(!names.contains("Deleted"))
    }

    @MainActor
    @Test("include_archived:false is identical to default (byte-identical path)")
    func includeFalseIsIdenticalToDefault() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let active = Project(name: "Work")
        let archived = Project(name: "Old")
        ctx.modelContext.context.insert(active)
        ctx.modelContext.context.insert(archived)
        try ctx.modelContext.context.save()
        try ctx.projectRepository.archive(archived)

        let defaultResult = try await ProjectsListTool().call(args: .object([:]), context: ctx)
        let explicitFalseResult = try await ProjectsListTool().call(
            args: .object(["include_archived": .bool(false)]),
            context: ctx
        )
        let defaultNames = try projectNames(from: defaultResult)
        let explicitNames = try projectNames(from: explicitFalseResult)

        #expect(defaultNames == explicitNames)
        #expect(defaultNames == ["Work"])
    }

    @MainActor
    @Test("include_archived rejects non-boolean value")
    func rejectsNonBooleanIncludeArchived() async throws {
        let fixture = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.validation("include_archived must be a boolean")) {
            _ = try await ProjectsListTool().call(
                args: .object(["include_archived": .string("yes")]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("archived_at field is populated in DTO when project is archived")
    func archivedAtPopulatedInDTO() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let project = Project(name: "Archivable")
        ctx.modelContext.context.insert(project)
        try ctx.modelContext.context.save()
        try ctx.projectRepository.archive(project)

        let result = try await ProjectsListTool().call(
            args: .object(["include_archived": .bool(true)]),
            context: ctx
        )
        let dtos = try projectDTOs(from: result)
        let found = try #require(dtos.first { $0.name == "Archivable" })

        #expect(found.archivedAt != nil)
    }

    // MARK: - tasks.orphaned

    @MainActor
    @Test("task on a deleted project is returned by tasks.orphaned")
    func orphanedTaskReturnedByTool() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let project = Project(name: "ToDelete")
        ctx.modelContext.context.insert(project)
        try ctx.modelContext.context.save()

        let orphan = TaskItem(title: "Orphan")
        try fixture.repo.insert(orphan)
        try fixture.repo.assign(orphan, toProject: project.id, section: nil)

        // Soft-delete the project so the task becomes orphaned.
        try ctx.projectRepository.softDelete(project)

        let result = try await TasksOrphanedTool().call(args: .object([:]), context: ctx)
        let orphans = try orphanedTasks(from: result)

        #expect(orphans.map(\.title) == ["Orphan"])
    }

    @MainActor
    @Test("task on a deleted project is excluded from tasks.list default (open state)")
    func orphanExcludedFromDefaultList() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let project = Project(name: "Gone")
        ctx.modelContext.context.insert(project)
        try ctx.modelContext.context.save()

        let orphan = TaskItem(title: "Orphan")
        let normal = TaskItem(title: "Normal")
        try fixture.repo.insert(orphan)
        try fixture.repo.insert(normal)
        try fixture.repo.assign(orphan, toProject: project.id, section: nil)

        try ctx.projectRepository.softDelete(project)

        let result = try await callTasksList(args: .object([:]), context: ctx)
        #expect(result.tasks.map(\.title) == ["Normal"])
        #expect(!result.tasks.contains { $0.title == "Orphan" })
    }

    @MainActor
    @Test("task on a deleted project appears with state=any")
    func orphanAppearsWithStateAny() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let project = Project(name: "Vanished")
        ctx.modelContext.context.insert(project)
        try ctx.modelContext.context.save()

        let orphan = TaskItem(title: "OrphanAny")
        let normal = TaskItem(title: "NormalAny")
        try fixture.repo.insert(orphan)
        try fixture.repo.insert(normal)
        try fixture.repo.assign(orphan, toProject: project.id, section: nil)

        try ctx.projectRepository.softDelete(project)

        let result = try await callTasksList(
            args: .object(["filter": .object(["state": .string("any")])]),
            context: ctx
        )
        let titles = Set(result.tasks.map(\.title))
        #expect(titles.contains("OrphanAny"))
        #expect(titles.contains("NormalAny"))
    }

    @MainActor
    @Test("tasks.orphaned excludes tasks on live projects")
    func nonOrphanExcludedFromOrphanedTool() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context
        let project = Project(name: "Live")
        ctx.modelContext.context.insert(project)
        try ctx.modelContext.context.save()

        let task = TaskItem(title: "NotOrphaned")
        try fixture.repo.insert(task)
        try fixture.repo.assign(task, toProject: project.id, section: nil)

        let result = try await TasksOrphanedTool().call(args: .object([:]), context: ctx)
        let orphans = try orphanedTasks(from: result)

        #expect(orphans.isEmpty)
    }

    @MainActor
    @Test("tasks.orphaned excludes unassigned tasks (inbox tasks are not orphans)")
    func inboxTasksNotOrphaned() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let ctx = fixture.context

        let inbox = TaskItem(title: "Inbox Task")
        try fixture.repo.insert(inbox)

        let result = try await TasksOrphanedTool().call(args: .object([:]), context: ctx)
        let orphans = try orphanedTasks(from: result)

        #expect(orphans.isEmpty)
    }

    @MainActor
    @Test("tasks.orphaned is registered in CoreTaskTools")
    func orphanedToolRegistered() {
        let names = Set(CoreTaskTools.all().map(\.name))
        #expect(names.contains("tasks.orphaned"))
    }

    // MARK: - Helpers

    private struct OrphanResponse: Decodable {
        // swiftlint:disable:next nesting
        struct OrphanDTO: Decodable {
            let title: String
        }

        let orphanedTasks: [OrphanDTO]
        let count: Int

        // swiftlint:disable:next nesting
        private enum CodingKeys: String, CodingKey {
            case orphanedTasks = "orphaned_tasks"
            case count
        }
    }

    private func projectNames(from result: JSONValue) throws -> [String] {
        try projectDTOs(from: result).map(\.name)
    }

    private func projectDTOs(from result: JSONValue) throws -> [ProjectDTO] {
        let data = try JSONEncoder().encode(result)
        let json = try JSONDecoder().decode([String: [ProjectDTO]].self, from: data)
        return json["projects"] ?? []
    }

    private func orphanedTasks(from result: JSONValue) throws -> [OrphanResponse.OrphanDTO] {
        let data = try JSONEncoder().encode(result)
        let response = try JSONDecoder().decode(OrphanResponse.self, from: data)
        return response.orphanedTasks
    }

    private func callTasksList(args: JSONValue, context: AgentContext) async throws -> TaskListResponseDTO {
        let result = try await TasksListTool().call(args: args, context: context)
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(TaskListResponseDTO.self, from: data)
    }
}
