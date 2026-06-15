import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TaskItemRepository.assignCycle")
struct TaskItemCycleAssignmentTests {
    private static let stamp = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 86_400

    @MainActor
    // swiftlint:disable:next large_tuple
    private func makeStack() throws -> (context: ModelContext, repo: TaskItemRepository, cycles: CycleRepository) {
        let schema = Schema([
            TaskItem.self, Cycle.self, ActivityEntry.self, Project.self, Section.self, Note.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Self.stamp },
            activity: ActivityRecorder(context: context)
        )
        let cycles = CycleRepository(context: context, now: { Self.stamp })
        return (context, repo, cycles)
    }

    @MainActor
    private func cycleChangedEntries(for taskID: UUID, in context: ModelContext) throws -> [ActivityEntry] {
        let kindRaw = ActivityEventKind.cycleChanged.rawValue
        let descriptor = FetchDescriptor<ActivityEntry>(
            predicate: #Predicate { entry in entry.itemID == taskID && entry.eventKindRaw == kindRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor)
    }

    private func payload(_ entry: ActivityEntry?) throws -> [String: Any] {
        let data = Data((entry?.payloadJSON ?? "{}").utf8)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    @MainActor
    @Test("assignCycle sets cycleID, bumps updatedAt, and records a cycleChanged event with old/new payload")
    func assignRecordsEvent() throws {
        let (context, repo, cycles) = try makeStack()
        let cycle = try cycles.create(
            name: "Sprint", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        let task = TaskItem(title: "Build")
        try repo.insert(task)

        try repo.assignCycle(task, to: cycle.id)

        #expect(task.cycleID == cycle.id)
        #expect(task.updatedAt == Self.stamp)

        let entries = try cycleChangedEntries(for: task.id, in: context)
        #expect(entries.count == 1)
        #expect(entries.first?.itemKindRaw == ItemKind.task.rawValue)
        let body = try payload(entries.first)
        #expect(body["new"] as? String == cycle.id.uuidString)
        #expect(body.keys.contains("old"))
    }

    @MainActor
    @Test("clearing the cycle records old/new and a no-op assignment records nothing")
    func clearAndNoop() throws {
        let (context, repo, cycles) = try makeStack()
        let cycle = try cycles.create(
            name: "Sprint", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        let task = TaskItem(title: "Build")
        try repo.insert(task)
        try repo.assignCycle(task, to: cycle.id)

        // No-op: same target, no second event.
        try repo.assignCycle(task, to: cycle.id)
        #expect(try cycleChangedEntries(for: task.id, in: context).count == 1)

        try repo.assignCycle(task, to: nil)
        #expect(task.cycleID == nil)
        let entries = try cycleChangedEntries(for: task.id, in: context)
        #expect(entries.count == 2)
        let body = try payload(entries.last)
        #expect(body["old"] as? String == cycle.id.uuidString)
    }

    @MainActor
    @Test("assignCycle rejects an unknown or soft-deleted cycle and leaves the task untouched")
    func rejectsDeadCycle() throws {
        let (context, repo, cycles) = try makeStack()
        let dead = try cycles.create(
            name: "Dead", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        try cycles.softDelete(dead)
        let task = TaskItem(title: "Build")
        try repo.insert(task)

        #expect(throws: TaskItemRepositoryError.cycleNotFound(cycleID: dead.id)) {
            try repo.assignCycle(task, to: dead.id)
        }
        let missing = UUID()
        #expect(throws: TaskItemRepositoryError.cycleNotFound(cycleID: missing)) {
            try repo.assignCycle(task, to: missing)
        }
        #expect(task.cycleID == nil)
        #expect(try cycleChangedEntries(for: task.id, in: context).isEmpty)
    }

    @MainActor
    @Test("assignCycle on a template is a no-op: no pointer, no event (I-D1)")
    func templateAssignmentIsNoOp() throws {
        let (context, repo, cycles) = try makeStack()
        let cycle = try cycles.create(
            name: "Sprint", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        let template = TaskItem(title: "Blueprint", isTemplate: true)
        try repo.insert(template)

        try repo.assignCycle(template, to: cycle.id)

        #expect(template.cycleID == nil)
        #expect(try cycleChangedEntries(for: template.id, in: context).isEmpty)
    }

    @MainActor
    @Test("a recurring task's spawned next occurrence does NOT carry cycleID (spec §4.2 no-carry pin)")
    func spawnDoesNotCarryCycle() throws {
        let (context, repo, cycles) = try makeStack()
        let cycle = try cycles.create(
            name: "Sprint", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        let task = TaskItem(title: "Standup", dueAt: Self.stamp, recurrenceRule: "FREQ=DAILY")
        try repo.insert(task)
        try repo.assignCycle(task, to: cycle.id)

        try repo.markDone(task)

        let parentID = task.id
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { item in item.recurrenceParentId == parentID }
        )
        let spawned = try context.fetch(descriptor)
        #expect(spawned.count == 1)
        #expect(spawned.first?.cycleID == nil)
        #expect(task.cycleID == cycle.id)  // the completed occurrence keeps its cycle (stats integrity)
    }
}
