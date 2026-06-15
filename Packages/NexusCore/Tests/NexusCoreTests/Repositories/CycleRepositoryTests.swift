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

    // MARK: - Plan C additions

    private static let day: TimeInterval = 86_400

    @MainActor
    @Test("create and update reject an end date not after the start date")
    func invalidIntervalRejected() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context, now: { self.start })

        #expect(throws: CycleRepositoryError.invalidInterval(startAt: start, endAt: start)) {
            try repo.create(name: "Bad", startAt: start, endAt: start)
        }

        let cycle = try repo.create(
            name: "Good", startAt: start, endAt: start.addingTimeInterval(Self.day)
        )
        #expect(throws: CycleRepositoryError.self) {
            try repo.update(
                cycle, name: "Good", startAt: start, endAt: start.addingTimeInterval(-Self.day)
            )
        }
    }

    @MainActor
    @Test("update rewrites name and interval and bumps updatedAt")
    func updateRewrites() throws {
        let context = try makeContext()
        var current = start
        let repo = CycleRepository(context: context, now: { current })
        let cycle = try repo.create(
            name: "Sprint 12", startAt: start, endAt: start.addingTimeInterval(7 * Self.day)
        )

        current = start.addingTimeInterval(Self.day)
        try repo.update(
            cycle,
            name: "Sprint 12 (extended)",
            startAt: start,
            endAt: start.addingTimeInterval(14 * Self.day)
        )

        #expect(cycle.name == "Sprint 12 (extended)")
        #expect(cycle.endAt == start.addingTimeInterval(14 * Self.day))
        #expect(cycle.updatedAt == current)
    }

    @MainActor
    @Test("current returns the active cycle containing now; ties resolve to earliest startAt")
    func currentSelection() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context, now: { self.start })
        let reference = start

        let older = try repo.create(
            name: "Old",
            startAt: reference.addingTimeInterval(-2 * Self.day),
            endAt: reference.addingTimeInterval(Self.day)
        )
        try repo.setStatus(.active, on: older)
        let newer = try repo.create(
            name: "New",
            startAt: reference.addingTimeInterval(-Self.day),
            endAt: reference.addingTimeInterval(Self.day)
        )
        try repo.setStatus(.active, on: newer)
        // Upcoming cycle containing now is NOT current — the machine is manual.
        _ = try repo.create(
            name: "Not started",
            startAt: reference.addingTimeInterval(-Self.day),
            endAt: reference.addingTimeInterval(Self.day)
        )

        #expect(try repo.current(now: reference)?.id == older.id)
    }

    @MainActor
    @Test("next returns the earliest not-completed cycle starting after now")
    func nextSelection() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context, now: { self.start })
        let reference = start

        let near = try repo.create(
            name: "Near",
            startAt: reference.addingTimeInterval(Self.day),
            endAt: reference.addingTimeInterval(2 * Self.day)
        )
        _ = try repo.create(
            name: "Far",
            startAt: reference.addingTimeInterval(3 * Self.day),
            endAt: reference.addingTimeInterval(4 * Self.day)
        )
        let completedFuture = try repo.create(
            name: "Done already",
            startAt: reference.addingTimeInterval(Self.day / 2),
            endAt: reference.addingTimeInterval(Self.day)
        )
        try repo.setStatus(.completed, on: completedFuture)

        #expect(try repo.next(now: reference)?.id == near.id)
        #expect(try repo.next(now: reference.addingTimeInterval(5 * Self.day)) == nil)
    }

    @MainActor
    @Test("tasks(in:) returns live non-template tasks of the cycle only")
    func tasksInCycle() throws {
        let context = try makeContext()
        let repo = CycleRepository(context: context, now: { self.start })
        let cycle = try repo.create(
            name: "Sprint", startAt: start, endAt: start.addingTimeInterval(Self.day)
        )
        let other = try repo.create(
            name: "Other", startAt: start, endAt: start.addingTimeInterval(Self.day)
        )

        let assigned = TaskItem(title: "In cycle")
        assigned.cycleID = cycle.id
        let elsewhere = TaskItem(title: "Other cycle")
        elsewhere.cycleID = other.id
        let deleted = TaskItem(title: "Deleted")
        deleted.cycleID = cycle.id
        deleted.deletedAt = start
        let template = TaskItem(title: "Template")
        template.cycleID = cycle.id
        template.isTemplate = true
        for task in [assigned, elsewhere, deleted, template] {
            context.insert(task)
        }
        try context.save()

        #expect(try repo.tasks(in: cycle.id).map(\.id) == [assigned.id])
    }
}
