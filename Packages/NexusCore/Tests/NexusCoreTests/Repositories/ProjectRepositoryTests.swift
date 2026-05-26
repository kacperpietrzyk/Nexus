import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ProjectRepository")
struct ProjectRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("create persists project and find returns it by id")
    func createAndFind() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = ProjectRepository(context: context, now: { stamp })

        let project = try repo.create(name: "Nexus", color: "gold")

        let fetched = try repo.find(id: project.id)
        #expect(fetched?.id == project.id)
        #expect(fetched?.name == "Nexus")
        #expect(fetched?.color == "gold")
        #expect(fetched?.createdAt == stamp)
        #expect(fetched?.updatedAt == stamp)
    }

    @MainActor
    @Test("allActive excludes archived and deleted projects sorted by name")
    func allActive() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)

        _ = try repo.create(name: "Zeta")
        _ = try repo.create(name: "Alpha")
        let archived = try repo.create(name: "Beta")
        let deleted = try repo.create(name: "Gamma")
        try repo.archive(archived)
        deleted.deletedAt = .now
        try context.save()

        let active = try repo.allActive()
        #expect(active.map(\.name) == ["Alpha", "Zeta"])
    }

    @MainActor
    @Test("archive cascades to child projects")
    func archiveCascade() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = ProjectRepository(context: context, now: { stamp })
        let root = try repo.create(name: "Root")
        let child = try repo.create(name: "Child", parentProjectID: root.id)
        let grandchild = try repo.create(name: "Grandchild", parentProjectID: child.id)
        let sibling = try repo.create(name: "Sibling")

        try repo.archive(root)

        #expect(root.archivedAt == stamp)
        #expect(child.archivedAt == stamp)
        #expect(grandchild.archivedAt == stamp)
        #expect(sibling.archivedAt == nil)
    }

    @MainActor
    @Test("archive handles cyclic project parent pointers")
    func archiveCycleGuard() throws {
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = ProjectRepository(context: context, now: { stamp })
        let root = try repo.create(name: "Root")
        let child = try repo.create(name: "Child", parentProjectID: root.id)
        root.parentProjectID = child.id
        try context.save()

        try repo.archive(root)

        #expect(root.archivedAt == stamp)
        #expect(child.archivedAt == stamp)
    }

    @MainActor
    @Test("archivedProjectIDs returns only non-deleted archived projects")
    func archivedProjectIDsReturnsArchivedSet() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let active = try repo.create(name: "Active")
        let archived = try repo.create(name: "Archived")
        let archivedDeleted = try repo.create(name: "Archived but deleted")
        try repo.archive(archived)
        try repo.archive(archivedDeleted)
        archivedDeleted.deletedAt = .now
        try context.save()

        let ids = try repo.archivedProjectIDs()

        #expect(ids == [archived.id])
        #expect(!ids.contains(active.id))
        #expect(!ids.contains(archivedDeleted.id))
    }

    @MainActor
    @Test("archive then unarchive toggles membership in archivedProjectIDs")
    func archiveUnarchiveTogglesSet() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let project = try repo.create(name: "Toggle")

        #expect(try repo.archivedProjectIDs().isEmpty)
        try repo.archive(project)
        #expect(try repo.archivedProjectIDs() == [project.id])
        try repo.unarchive(project)
        #expect(try repo.archivedProjectIDs().isEmpty)
    }

    @MainActor
    @Test("rename recolor and unarchive update lifecycle fields")
    func renameRecolorUnarchive() throws {
        var current = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let repo = ProjectRepository(context: context, now: { current })
        let project = try repo.create(name: "Old", color: "azure")

        current = current.addingTimeInterval(60)
        try repo.rename(project, to: "New")
        #expect(project.name == "New")
        #expect(project.updatedAt == current)

        current = current.addingTimeInterval(60)
        try repo.recolor(project, to: "rose")
        #expect(project.color == "rose")
        #expect(project.updatedAt == current)

        try repo.archive(project)
        current = current.addingTimeInterval(60)
        try repo.unarchive(project)
        #expect(project.archivedAt == nil)
        #expect(project.updatedAt == current)
    }
}
