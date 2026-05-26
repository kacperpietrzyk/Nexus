import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository assignment")
struct TaskItemAssignmentTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, Section.self, Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("assign moves a task between project section and project root")
    func assignAndReassign() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let project = Project(name: "Project")
        let projectID = project.id
        let section = Section(projectID: projectID, name: "Doing")
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let task = TaskItem(title: "task")
        context.insert(project)
        context.insert(section)
        try repo.insert(task)

        try repo.assign(task, toProject: projectID, section: section.id)
        #expect(task.projectID == projectID)
        #expect(task.sectionID == section.id)
        #expect(task.updatedAt == stamp)

        try repo.assign(task, toProject: projectID)
        #expect(task.projectID == projectID)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects a section without a project")
    func assignRejectsSectionWithoutProject() throws {
        let sectionID = UUID()
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let task = TaskItem(title: "task")
        try repo.insert(task)

        #expect(throws: ProjectSectionAssignmentError.sectionRequiresProject(sectionID: sectionID)) {
            try repo.assign(task, toProject: nil, section: sectionID)
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects nonexistent section IDs")
    func assignRejectsMissingSection() throws {
        let project = Project(name: "P")
        let projectID = project.id
        let sectionID = UUID()
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let task = TaskItem(title: "task")
        context.insert(project)
        try repo.insert(task)

        #expect(throws: ProjectSectionAssignmentError.sectionNotFound(sectionID: sectionID)) {
            try repo.assign(task, toProject: projectID, section: sectionID)
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects deleted section IDs")
    func assignRejectsDeletedSection() throws {
        let project = Project(name: "P")
        let projectID = project.id
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let section = Section(projectID: projectID, name: "Deleted")
        section.deletedAt = .now
        let task = TaskItem(title: "task")
        context.insert(project)
        context.insert(section)
        try repo.insert(task)

        #expect(throws: ProjectSectionAssignmentError.sectionNotFound(sectionID: section.id)) {
            try repo.assign(task, toProject: projectID, section: section.id)
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects a section from another project")
    func assignRejectsCrossProjectSection() throws {
        let project = Project(name: "P")
        let otherProject = Project(name: "Other")
        let projectID = project.id
        let otherProjectID = otherProject.id
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let section = Section(projectID: otherProjectID, name: "Elsewhere")
        let task = TaskItem(title: "task")
        context.insert(project)
        context.insert(otherProject)
        context.insert(section)
        try repo.insert(task)

        #expect(
            throws: ProjectSectionAssignmentError.sectionProjectMismatch(
                sectionID: section.id,
                expectedProjectID: projectID,
                actualProjectID: otherProjectID
            )
        ) {
            try repo.assign(task, toProject: projectID, section: section.id)
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects unknown project IDs")
    func assignRejectsUnknownProject() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let unknownID = UUID()
        let task = TaskItem(title: "task")
        try repo.insert(task)

        #expect(throws: TaskItemRepositoryError.projectNotFound(projectID: unknownID)) {
            try repo.assign(task, toProject: unknownID)
        }
        #expect(task.projectID == nil)
        #expect(task.sectionID == nil)
    }

    @MainActor
    @Test("assign rejects soft-deleted project IDs")
    func assignRejectsSoftDeletedProject() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let project = Project(name: "Gone")
        project.deletedAt = .now
        context.insert(project)
        let task = TaskItem(title: "task")
        try repo.insert(task)

        #expect(throws: TaskItemRepositoryError.projectNotFound(projectID: project.id)) {
            try repo.assign(task, toProject: project.id)
        }
        #expect(task.projectID == nil)
    }

    @MainActor
    @Test("assign accepts archived project IDs")
    func assignAcceptsArchivedProject() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let project = Project(name: "Archived")
        project.archivedAt = .now
        context.insert(project)
        let task = TaskItem(title: "task")
        try repo.insert(task)

        try repo.assign(task, toProject: project.id)
        #expect(task.projectID == project.id)
    }

    @MainActor
    @Test("tasks in section filter soft-deleted tasks and sort by order then createdAt")
    func tasksInSectionFilterAndSort() throws {
        let projectID = UUID()
        let sectionID = UUID()
        let otherSectionID = UUID()
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let orderedFirst = TaskItem(title: "ordered first", projectID: projectID, sectionID: sectionID, orderIndex: 1.0)
        let orderedSecond = TaskItem(title: "ordered second", projectID: projectID, sectionID: sectionID, orderIndex: 2.0)
        let olderUnordered = TaskItem(title: "older unordered", projectID: projectID, sectionID: sectionID)
        let newerUnordered = TaskItem(title: "newer unordered", projectID: projectID, sectionID: sectionID)
        let deleted = TaskItem(title: "deleted", projectID: projectID, sectionID: sectionID, orderIndex: 0.5)
        let otherSection = TaskItem(title: "other", projectID: projectID, sectionID: otherSectionID, orderIndex: 0.25)

        orderedFirst.createdAt = base.addingTimeInterval(30)
        orderedSecond.createdAt = base.addingTimeInterval(10)
        olderUnordered.createdAt = base
        newerUnordered.createdAt = base.addingTimeInterval(60)
        deleted.deletedAt = base

        for task in [orderedSecond, newerUnordered, deleted, olderUnordered, orderedFirst, otherSection] {
            context.insert(task)
        }
        try context.save()

        let tasks = try repo.tasks(in: projectID, section: sectionID)
        #expect(tasks.map(\.title) == ["ordered first", "ordered second", "older unordered", "newer unordered"])
    }

    @MainActor
    @Test("tasks in project return root and section tasks scoped to that project")
    func tasksInProject() throws {
        let projectID = UUID()
        let otherProjectID = UUID()
        let sectionID = UUID()
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let root = TaskItem(title: "root", projectID: projectID, sectionID: nil)
        let section = TaskItem(title: "section", projectID: projectID, sectionID: sectionID)
        let deleted = TaskItem(title: "deleted", projectID: projectID, sectionID: sectionID)
        let otherRoot = TaskItem(title: "other root", projectID: otherProjectID, sectionID: nil)
        root.createdAt = base
        section.createdAt = base.addingTimeInterval(60)
        deleted.deletedAt = base
        context.insert(root)
        context.insert(section)
        context.insert(deleted)
        context.insert(otherRoot)
        try context.save()

        #expect(try repo.tasks(in: projectID).map(\.title) == ["root", "section"])
    }
}
