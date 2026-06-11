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
    @Test("findActive(matchingToken:) matches case-insensitively, with space-stripped names, active only")
    func findActiveMatchingToken() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let nexus = try repo.create(name: "Nexus")
        let side = try repo.create(name: "Side Project")
        let archived = try repo.create(name: "Frozen")
        try repo.archive(archived)
        let deleted = try repo.create(name: "Gone")
        deleted.deletedAt = .now
        try context.save()

        // exact, case-insensitive
        #expect(try repo.findActive(matchingToken: "nexus")?.id == nexus.id)
        #expect(try repo.findActive(matchingToken: "NEXUS")?.id == nexus.id)
        // multi-word project reachable via space-stripped form
        #expect(try repo.findActive(matchingToken: "SideProject")?.id == side.id)
        #expect(try repo.findActive(matchingToken: "sideproject")?.id == side.id)
        // archived / deleted / unknown / empty ⇒ nil
        #expect(try repo.findActive(matchingToken: "frozen") == nil)
        #expect(try repo.findActive(matchingToken: "gone") == nil)
        #expect(try repo.findActive(matchingToken: "missing") == nil)
        #expect(try repo.findActive(matchingToken: "") == nil)
    }

    @MainActor
    @Test("findActive(matchingToken:) prefers an exact name match over a space-stripped match")
    func findActiveExactBeatsStripped() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        // "A BC" sorts before "ABC" and matches "abc" via space-stripping, but
        // the exact-match pass must win regardless of sort order.
        let spaced = try repo.create(name: "A BC")
        let exact = try repo.create(name: "ABC")

        #expect(try repo.findActive(matchingToken: "ABC")?.id == exact.id)
        #expect(try repo.findActive(matchingToken: "abc")?.id == exact.id)
        // Without an exact candidate the stripped pass still resolves.
        try repo.softDelete(exact)
        #expect(try repo.findActive(matchingToken: "abc")?.id == spaced.id)
    }

    @MainActor
    @Test("findActive(matchingToken:) tie-break is deterministic: name, then UUID string")
    func findActiveTieBreakDeterministic() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let first = try repo.create(name: "Dup")
        let second = try repo.create(name: "Dup")
        let expected = [first, second].min { $0.id.uuidString < $1.id.uuidString }

        for _ in 0..<5 {
            #expect(try repo.findActive(matchingToken: "dup")?.id == expected?.id)
        }
    }

    @MainActor
    @Test("findActive(matchingToken:) resolves a multi-word token via the exact pass (FM-path shape)")
    func findActiveMultiWordToken() throws {
        // The handcoded parser only emits single-word tokens, but the FM path
        // can return a project's full multi-word name as the token. Pin: such
        // a token resolves through the exact lowercased-name match.
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let side = try repo.create(name: "Side Project")

        #expect(try repo.findActive(matchingToken: "Side Project")?.id == side.id)
        #expect(try repo.findActive(matchingToken: "side project")?.id == side.id)
    }

    @MainActor
    @Test("findActive(matchingToken:) matches diacritic names case-insensitively")
    func findActiveDiacriticName() throws {
        let context = try makeContext()
        let repo = ProjectRepository(context: context)
        let project = try repo.create(name: "Prząśnik")

        #expect(try repo.findActive(matchingToken: "Prząśnik")?.id == project.id)
        #expect(try repo.findActive(matchingToken: "prząśnik")?.id == project.id)
        #expect(try repo.findActive(matchingToken: "PRZĄŚNIK")?.id == project.id)
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
