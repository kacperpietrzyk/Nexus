import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("CycleRepository")
struct CycleRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Cycle.self, TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let end = Date(timeIntervalSince1970: 1_700_600_000)

    @MainActor
    @Test("create persists with the injected timestamp")
    func createPersistsWithInjectedStamp() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_750_000_000)
        let repo = CycleRepository(context: context, now: { stamp })

        let cycle = try repo.create(name: "Sprint 1", startAt: start, endAt: end)
        #expect(cycle.name == "Sprint 1")
        #expect(cycle.startAt == start)
        #expect(cycle.endAt == end)
        #expect(cycle.status == .upcoming)
        #expect(cycle.createdAt == stamp)
        #expect(cycle.updatedAt == stamp)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
    }

    @MainActor
    @Test("allActive excludes soft-deleted and sorts by startAt ascending")
    func allActiveExcludesDeletedSortsByStart() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context)

        let second = try repo.create(name: "Sprint 2", startAt: end, endAt: end.addingTimeInterval(600_000))
        let first = try repo.create(name: "Sprint 1", startAt: start, endAt: end)
        let deleted = try repo.create(name: "Gone", startAt: start, endAt: end)
        try repo.softDelete(deleted)

        let active = try repo.allActive()
        #expect(active.map(\.id) == [first.id, second.id])
    }

    @MainActor
    @Test("rename and setDates bump updatedAt")
    func renameAndSetDatesBumpUpdatedAt() throws {
        let context = try makeContext()
        var stamp = Date(timeIntervalSince1970: 1_750_000_000)
        let repo = CycleRepository(context: context, now: { stamp })
        let cycle = try repo.create(name: "Sprint 1", startAt: start, endAt: end)

        stamp = stamp.addingTimeInterval(60)
        try repo.rename(cycle, to: "Sprint 1b")
        #expect(cycle.name == "Sprint 1b")
        #expect(cycle.updatedAt == stamp)

        stamp = stamp.addingTimeInterval(60)
        let newEnd = end.addingTimeInterval(86_400)
        try repo.setDates(cycle, startAt: start, endAt: newEnd)
        #expect(cycle.endAt == newEnd)
        #expect(cycle.updatedAt == stamp)
    }

    @MainActor
    @Test("setStatus walks the manual machine (no auto-rollover — I-C1)")
    func setStatusUpdatesRaw() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context)
        let cycle = try repo.create(name: "Sprint 1", startAt: start, endAt: end)

        try repo.setStatus(.active, on: cycle)
        #expect(cycle.status == .active)
        try repo.setStatus(.completed, on: cycle)
        #expect(cycle.statusRaw == "completed")
    }

    @MainActor
    @Test("softDelete leaves assigned tasks' cycleID dangling (projectID semantics)")
    func softDeleteLeavesTaskCycleIDDangling() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context)
        let cycle = try repo.create(name: "Sprint 1", startAt: start, endAt: end)

        let task = TaskItem(title: "in sprint", cycleID: cycle.id)
        context.insert(task)
        try context.save()

        try repo.softDelete(cycle)
        #expect(cycle.deletedAt != nil)
        #expect(task.cycleID == cycle.id)  // KEPT — dangling resolves to "no cycle" at read time.
        #expect(try repo.allActive().isEmpty)
    }

    @MainActor
    @Test("find returns a cycle by id, nil for unknown")
    func findByID() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context)
        let cycle = try repo.create(name: "Sprint 1", startAt: start, endAt: end)

        #expect(try repo.find(id: cycle.id)?.id == cycle.id)
        #expect(try repo.find(id: UUID()) == nil)
    }
}
