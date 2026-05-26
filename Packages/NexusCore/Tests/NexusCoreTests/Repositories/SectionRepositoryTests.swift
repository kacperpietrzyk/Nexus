import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("SectionRepository")
struct SectionRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, Section.self, TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("create appends sections after existing order indexes")
    func createAppendsAfterExisting() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()

        let first = try repo.create(projectID: projectID, name: "Backlog")
        let second = try repo.create(projectID: projectID, name: "Next")
        let third = try repo.create(projectID: projectID, name: "Doing")

        #expect(first.orderIndex == 1.0)
        #expect(second.orderIndex == 2.0)
        #expect(third.orderIndex == 3.0)
        #expect(try repo.sections(in: projectID).map(\.name) == ["Backlog", "Next", "Doing"])
    }

    @MainActor
    @Test("sections are scoped to project and sorted by orderIndex")
    func sectionsScopedAndSorted() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()
        let otherProjectID = UUID()
        let later = Section(projectID: projectID, name: "Later", orderIndex: 10.0)
        let now = Section(projectID: projectID, name: "Now", orderIndex: 1.0)
        let deleted = Section(projectID: projectID, name: "Deleted", orderIndex: 0.5)
        let other = Section(projectID: otherProjectID, name: "Other", orderIndex: 0.25)
        deleted.deletedAt = .now
        context.insert(later)
        context.insert(now)
        context.insert(deleted)
        context.insert(other)
        try context.save()

        let sections = try repo.sections(in: projectID)
        #expect(sections.map(\.name) == ["Now", "Later"])
    }

    @MainActor
    @Test("reorder assigns midpoint between neighbors")
    func reorderMidpoint() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()
        let first = try repo.create(projectID: projectID, name: "First")
        let second = try repo.create(projectID: projectID, name: "Second")
        let third = try repo.create(projectID: projectID, name: "Third")

        try repo.reorder(third, after: first, before: second)

        #expect(third.orderIndex == 1.5)
        #expect(try repo.sections(in: projectID).map(\.name) == ["First", "Third", "Second"])
    }

    @MainActor
    @Test("delete reassigns live tasks to destination section")
    func deleteReassignsTasksToDestination() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = SectionRepository(context: context, now: { stamp })
        let projectID = UUID()
        let source = try repo.create(projectID: projectID, name: "Source")
        let destination = try repo.create(projectID: projectID, name: "Destination")
        let live = TaskItem(title: "live", projectID: projectID, sectionID: source.id)
        let deleted = TaskItem(title: "deleted", projectID: projectID, sectionID: source.id)
        deleted.deletedAt = stamp.addingTimeInterval(-60)
        context.insert(live)
        context.insert(deleted)
        try context.save()

        try repo.delete(source, reassignTasksTo: destination.id)

        #expect(source.deletedAt == stamp)
        #expect(live.projectID == projectID)
        #expect(live.sectionID == destination.id)
        #expect(live.updatedAt == stamp)
        #expect(deleted.sectionID == source.id)
    }

    @MainActor
    @Test("delete rejects reassigning tasks to the deleted section itself")
    func deleteRejectsSameSectionDestination() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()
        let source = try repo.create(projectID: projectID, name: "Source")
        let task = TaskItem(title: "task", projectID: projectID, sectionID: source.id)
        context.insert(task)
        try context.save()

        #expect(throws: ProjectSectionAssignmentError.cannotReassignSectionToItself(sectionID: source.id)) {
            try repo.delete(source, reassignTasksTo: source.id)
        }
        #expect(source.deletedAt == nil)
        #expect(task.projectID == projectID)
        #expect(task.sectionID == source.id)
    }

    @MainActor
    @Test("delete rejects reassigning tasks to a section from another project")
    func deleteRejectsCrossProjectDestination() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()
        let otherProjectID = UUID()
        let source = try repo.create(projectID: projectID, name: "Source")
        let destination = try repo.create(projectID: otherProjectID, name: "Elsewhere")
        let task = TaskItem(title: "task", projectID: projectID, sectionID: source.id)
        context.insert(task)
        try context.save()

        #expect(
            throws: ProjectSectionAssignmentError.sectionProjectMismatch(
                sectionID: destination.id,
                expectedProjectID: projectID,
                actualProjectID: otherProjectID
            )
        ) {
            try repo.delete(source, reassignTasksTo: destination.id)
        }
        #expect(source.deletedAt == nil)
        #expect(task.projectID == projectID)
        #expect(task.sectionID == source.id)
    }

    @MainActor
    @Test("delete reassigns tasks to project root when destination is nil")
    func deleteReassignsTasksToProjectRoot() throws {
        let context = try makeContext()
        let repo = SectionRepository(context: context)
        let projectID = UUID()
        let source = try repo.create(projectID: projectID, name: "Source")
        let task = TaskItem(title: "task", projectID: projectID, sectionID: source.id)
        context.insert(task)
        try context.save()

        try repo.delete(source)

        #expect(task.projectID == projectID)
        #expect(task.sectionID == nil)
    }
}
