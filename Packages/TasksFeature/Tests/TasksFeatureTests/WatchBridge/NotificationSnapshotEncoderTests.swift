import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("NotificationSnapshotEncoder")
@MainActor
struct NotificationSnapshotEncoderTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func includes_only_open_with_dueAt_in_window() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let inWindow = TaskItem(title: "soon", dueAt: now.addingTimeInterval(3_600))
        let outOfWindow = TaskItem(title: "next week", dueAt: now.addingTimeInterval(7 * 86_400))
        let noDue = TaskItem(title: "no due")
        let done = TaskItem(title: "done", dueAt: now.addingTimeInterval(60))
        done.statusRaw = TaskStatus.done.rawValue
        let deleted = TaskItem(title: "deleted", dueAt: now.addingTimeInterval(60))
        deleted.deletedAt = now

        for t in [inWindow, outOfWindow, noDue, done, deleted] { context.insert(t) }
        try context.save()

        let encoder = NotificationSnapshotEncoder(context: context)
        let snapshot = encoder.encode(now: now, horizon: 24 * 3_600)

        #expect(snapshot.entries.map(\.id) == [inWindow.id])
        #expect(snapshot.horizon == 24 * 3_600)
        #expect(snapshot.generatedAt == now)
    }

    @Test func uses_snoozedUntil_as_effective_trigger_when_present() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let task = TaskItem(title: "snoozed", dueAt: now.addingTimeInterval(60))
        task.snoozedUntil = now.addingTimeInterval(3_600)
        context.insert(task)
        try context.save()

        let encoder = NotificationSnapshotEncoder(context: context)
        let snapshot = encoder.encode(now: now, horizon: 24 * 3_600)

        #expect(snapshot.entries.first?.snoozedUntil == now.addingTimeInterval(3_600))
        #expect(snapshot.entries.first?.effectiveTriggerAt == now.addingTimeInterval(3_600))
    }

    @Test func sorts_entries_ascending_by_effective_trigger() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let later = TaskItem(title: "later", dueAt: now.addingTimeInterval(7_200))
        let sooner = TaskItem(title: "sooner", dueAt: now.addingTimeInterval(60))
        context.insert(later)
        context.insert(sooner)
        try context.save()

        let snapshot = NotificationSnapshotEncoder(context: context)
            .encode(now: now, horizon: 24 * 3_600)

        #expect(snapshot.entries.map(\.title) == ["sooner", "later"])
    }
}
