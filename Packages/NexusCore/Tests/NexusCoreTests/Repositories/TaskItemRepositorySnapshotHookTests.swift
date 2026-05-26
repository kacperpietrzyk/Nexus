import Foundation
import SwiftData
import Testing

@testable import NexusCore

private actor PusherRecorder {
    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Int, Never>
    }

    private(set) var count = 0
    private var waiters: [CountWaiter] = []

    func bump() {
        count += 1
        resolveWaiters()
    }

    func waitForCount(_ expectedCount: Int) async -> Int {
        if count >= expectedCount {
            return count
        }

        return await withCheckedContinuation { continuation in
            waiters.append(CountWaiter(expectedCount: expectedCount, continuation: continuation))
        }
    }

    private func resolveWaiters() {
        let ready = waiters.filter { count >= $0.expectedCount }
        waiters.removeAll { count >= $0.expectedCount }
        for waiter in ready {
            waiter.continuation.resume(returning: count)
        }
    }
}

@Suite("TaskItemRepository snapshot pusher hook")
@MainActor
struct TaskItemRepositorySnapshotHookTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test(.timeLimit(.minutes(1))) func insert_calls_pusher_once() async throws {
        let context = try makeContext()
        let recorder = PusherRecorder()
        let pusher: WatchSnapshotPusher = { await recorder.bump() }
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date() },
            notifications: NoopNotificationScheduler(),
            snapshotPusher: pusher
        )
        try repo.insert(TaskItem(title: "x", dueAt: Date().addingTimeInterval(60)))
        let count = await recorder.waitForCount(1)
        #expect(count == 1)
    }

    @Test(.timeLimit(.minutes(1))) func snooze_calls_pusher() async throws {
        let context = try makeContext()
        let recorder = PusherRecorder()
        let pusher: WatchSnapshotPusher = { await recorder.bump() }
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { Date() },
            notifications: NoopNotificationScheduler(),
            snapshotPusher: pusher
        )
        let task = TaskItem(title: "x", dueAt: Date().addingTimeInterval(60))
        try repo.insert(task)
        let insertCount = await recorder.waitForCount(1)
        #expect(insertCount == 1)
        try repo.snooze(task, until: Date().addingTimeInterval(3600))
        let count = await recorder.waitForCount(2)
        #expect(count == 2)
    }
}
