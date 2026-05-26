import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusWatch

@Suite("WatchTaskActions")
struct WatchTaskActionsTests {
    @MainActor
    private final class FakeBridge: WatchActionSending {
        var markDoneCalls: [UUID] = []
        var reopenCalls: [UUID] = []
        var snoozeCalls: [(UUID, Date)] = []
        var shouldThrow: Error?

        func sendMarkDone(taskID: UUID) async throws {
            if let shouldThrow { throw shouldThrow }
            markDoneCalls.append(taskID)
        }

        func sendReopen(taskID: UUID) async throws {
            if let shouldThrow { throw shouldThrow }
            reopenCalls.append(taskID)
        }

        func sendSnoozeAction(taskID: UUID, until: Date) async throws {
            if let shouldThrow { throw shouldThrow }
            snoozeCalls.append((taskID, until))
        }
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("markDone flips status and calls bridge once")
    func markDoneFlipsAndSends() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "x", dueAt: .now)
        context.insert(task)
        let bridge = FakeBridge()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let actions = WatchTaskActions(context: context, bridge: bridge, now: { stamp })

        try await actions.markDone(task)

        #expect(task.statusRaw == TaskStatus.done.rawValue)
        #expect(task.lastCompletedAt == stamp)
        #expect(task.updatedAt == stamp)
        #expect(bridge.markDoneCalls == [task.id])
    }

    @MainActor
    @Test("reopen reverts status and calls bridge once")
    func reopenRevertsAndSends() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "x", dueAt: .now)
        task.statusRaw = TaskStatus.done.rawValue
        task.lastCompletedAt = .now
        context.insert(task)
        let bridge = FakeBridge()
        let actions = WatchTaskActions(context: context, bridge: bridge)

        try await actions.reopen(task)

        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
        #expect(bridge.reopenCalls == [task.id])
    }

    @MainActor
    @Test("markDone twice in a row is idempotent on Watch side")
    func markDoneIdempotent() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "x", dueAt: .now)
        context.insert(task)
        let bridge = FakeBridge()
        let actions = WatchTaskActions(context: context, bridge: bridge)

        try await actions.markDone(task)
        try await actions.markDone(task)

        #expect(bridge.markDoneCalls.count == 1)
    }

    @MainActor
    @Test("Bridge throwing surfaces the error")
    func bridgeThrowsPropagates() async throws {
        struct FakeError: Error {}
        let context = try makeContext()
        let task = TaskItem(title: "x", dueAt: .now)
        context.insert(task)
        let bridge = FakeBridge()
        bridge.shouldThrow = FakeError()
        let actions = WatchTaskActions(context: context, bridge: bridge)

        await #expect(throws: FakeError.self) {
            try await actions.markDone(task)
        }
        #expect(task.statusRaw == TaskStatus.done.rawValue)
    }

    @MainActor
    @Test("reopen on already-open task does not call bridge")
    func reopenIdempotent() async throws {
        let context = try makeContext()
        let task = TaskItem(title: "x", dueAt: .now)
        context.insert(task)
        let bridge = FakeBridge()
        let actions = WatchTaskActions(context: context, bridge: bridge)

        try await actions.reopen(task)

        #expect(bridge.reopenCalls.isEmpty)
    }
}
