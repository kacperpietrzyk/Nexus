import Foundation
import SwiftData
import Testing

@testable import NexusCore

private actor SubtaskNotificationRecorder {
    private struct IDWaiter {
        let expectedIDs: Set<UUID>
        let continuation: CheckedContinuation<Set<UUID>, Never>
    }

    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<[UUID], Never>
    }

    private var canceledTaskIDs = Set<UUID>()
    private var scheduledTaskIDs: [UUID] = []
    private var cancelWaiters: [IDWaiter] = []
    private var scheduleWaiters: [CountWaiter] = []

    func recordCancel(taskID: UUID) {
        canceledTaskIDs.insert(taskID)
        resolveCancelWaiters()
    }

    func recordSchedule(taskID: UUID) {
        scheduledTaskIDs.append(taskID)
        resolveScheduleWaiters()
    }

    func waitForCanceledIDs(_ expectedIDs: Set<UUID>) async -> Set<UUID> {
        if expectedIDs.isSubset(of: canceledTaskIDs) {
            return canceledTaskIDs
        }

        return await withCheckedContinuation { continuation in
            cancelWaiters.append(IDWaiter(expectedIDs: expectedIDs, continuation: continuation))
        }
    }

    func waitForScheduledCount(_ expectedCount: Int) async -> [UUID] {
        if scheduledTaskIDs.count >= expectedCount {
            return scheduledTaskIDs
        }

        return await withCheckedContinuation { continuation in
            scheduleWaiters.append(CountWaiter(expectedCount: expectedCount, continuation: continuation))
        }
    }

    private func resolveCancelWaiters() {
        let ready = cancelWaiters.filter { $0.expectedIDs.isSubset(of: canceledTaskIDs) }
        cancelWaiters.removeAll { $0.expectedIDs.isSubset(of: canceledTaskIDs) }
        for waiter in ready {
            waiter.continuation.resume(returning: canceledTaskIDs)
        }
    }

    private func resolveScheduleWaiters() {
        let ready = scheduleWaiters.filter { scheduledTaskIDs.count >= $0.expectedCount }
        scheduleWaiters.removeAll { scheduledTaskIDs.count >= $0.expectedCount }
        for waiter in ready {
            waiter.continuation.resume(returning: scheduledTaskIDs)
        }
    }
}

private actor SubtaskPusherRecorder {
    private struct CountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Int, Never>
    }

    private var pushCount = 0
    private var waiters: [CountWaiter] = []

    func bump() {
        pushCount += 1
        resolveWaiters()
    }

    func waitForCount(_ expectedCount: Int) async -> Int {
        if pushCount >= expectedCount {
            return pushCount
        }

        return await withCheckedContinuation { continuation in
            waiters.append(CountWaiter(expectedCount: expectedCount, continuation: continuation))
        }
    }

    private func resolveWaiters() {
        let ready = waiters.filter { pushCount >= $0.expectedCount }
        waiters.removeAll { pushCount >= $0.expectedCount }
        for waiter in ready {
            waiter.continuation.resume(returning: pushCount)
        }
    }
}

private struct RecordingSubtaskNotificationScheduler: NotificationScheduling {
    let recorder: SubtaskNotificationRecorder

    func schedule(_ task: TaskItem) async throws {
        await recorder.recordSchedule(taskID: task.id)
    }

    func cancel(taskID: UUID) async {
        await recorder.recordCancel(taskID: taskID)
    }

    func reschedule(_: TaskItem) async throws {}

    func scheduleSnooze(_: TaskItem, until _: Date) async throws {}
}

@Suite("TaskItemRepository subtasks")
struct TaskItemSubtaskTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    @Test("subtasks excludes done and snoozed children")
    func subtasksExcludesDoneAndSnoozedChildren() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let parent = TaskItem(title: "parent")
        let openChild = TaskItem(title: "open", parentTaskID: parent.id, orderIndex: 1)
        let doneChild = TaskItem(title: "done", status: .done, parentTaskID: parent.id, orderIndex: 2)
        let snoozedChild = TaskItem(
            title: "snoozed",
            status: .snoozed,
            parentTaskID: parent.id,
            orderIndex: 3
        )
        for task in [parent, openChild, doneChild, snoozedChild] {
            context.insert(task)
        }
        try context.save()

        #expect(try repo.subtasks(of: parent).map(\.title) == ["open"])
        // `allSubtasks(of:)` mirrors the previous loose semantics.
        let allTitles = try repo.allSubtasks(of: parent).map(\.title).sorted()
        #expect(allTitles == ["done", "open", "snoozed"])
    }

    @MainActor
    @Test("subtasks returns active children of the parent sorted by order then createdAt")
    func subtasksFilterAndSort() throws {
        let context = try makeContext()
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let parent = TaskItem(title: "parent")
        let otherParent = TaskItem(title: "other parent")
        let first = TaskItem(title: "first", parentTaskID: parent.id, orderIndex: 1)
        let second = TaskItem(title: "second", parentTaskID: parent.id, orderIndex: 2)
        let unordered = TaskItem(title: "unordered", parentTaskID: parent.id)
        let deleted = TaskItem(title: "deleted", parentTaskID: parent.id, orderIndex: 0)
        let otherChild = TaskItem(title: "other child", parentTaskID: otherParent.id, orderIndex: 0.5)

        first.createdAt = base.addingTimeInterval(30)
        second.createdAt = base
        unordered.createdAt = base.addingTimeInterval(60)
        deleted.deletedAt = base

        for task in [parent, otherParent, second, unordered, deleted, first, otherChild] {
            context.insert(task)
        }
        try context.save()

        let subtasks = try repo.subtasks(of: parent)

        #expect(subtasks.map(\.title) == ["first", "second", "unordered"])
    }

    @MainActor
    @Test("markDoneStrict throws when direct children are open")
    func markDoneStrictThrowsForOpenDirectChildren() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent")
        let openChild = TaskItem(title: "open child", parentTaskID: parent.id)
        let doneChild = TaskItem(title: "done child", status: .done, parentTaskID: parent.id)
        doneChild.lastCompletedAt = stamp.addingTimeInterval(-60)

        for task in [parent, openChild, doneChild] {
            context.insert(task)
        }
        try context.save()

        #expect(throws: TaskItemRepositoryError.parentHasOpenSubtasks(parentID: parent.id, openCount: 1)) {
            try repo.markDoneStrict(parent)
        }
        #expect(parent.statusRaw == TaskStatus.open.rawValue)
        #expect(parent.lastCompletedAt == nil)
    }

    @MainActor
    @Test("markDoneStrict succeeds when direct children are done or absent")
    func markDoneStrictSucceedsWithoutOpenDirectChildren() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parentWithDoneChild = TaskItem(title: "parent with done child")
        let doneChild = TaskItem(title: "done child", status: .done, parentTaskID: parentWithDoneChild.id)
        let parentWithoutChildren = TaskItem(title: "parent without children")
        doneChild.lastCompletedAt = stamp.addingTimeInterval(-60)

        for task in [parentWithDoneChild, doneChild, parentWithoutChildren] {
            context.insert(task)
        }
        try context.save()

        try repo.markDoneStrict(parentWithDoneChild)
        try repo.markDoneStrict(parentWithoutChildren)

        #expect(parentWithDoneChild.statusRaw == TaskStatus.done.rawValue)
        #expect(parentWithDoneChild.lastCompletedAt == stamp)
        #expect(parentWithoutChildren.statusRaw == TaskStatus.done.rawValue)
        #expect(parentWithoutChildren.lastCompletedAt == stamp)
    }

    @MainActor
    @Test("cascadeComplete closes the entire subtree including grandchildren")
    func cascadeCompleteClosesDescendants() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentTaskID: parent.id)
        let grandchild = TaskItem(title: "grandchild", parentTaskID: child.id)
        let otherRoot = TaskItem(title: "other root")

        for task in [parent, child, grandchild, otherRoot] {
            context.insert(task)
        }
        try context.save()

        try repo.cascadeComplete(parent)

        for task in [parent, child, grandchild] {
            #expect(task.statusRaw == TaskStatus.done.rawValue)
            #expect(task.lastCompletedAt == stamp)
            #expect(task.updatedAt == stamp)
        }
        #expect(otherRoot.statusRaw == TaskStatus.open.rawValue)
        #expect(otherRoot.lastCompletedAt == nil)
    }

    @MainActor
    @Test("cascadeComplete preserves recurring completion behavior")
    func cascadeCompletePreservesRecurringCompletionBehavior() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let childDueAt = stamp.addingTimeInterval(3_600)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent", dueAt: stamp, recurrenceRule: "FREQ=DAILY")
        let child = TaskItem(
            title: "child",
            dueAt: childDueAt,
            recurrenceRule: "FREQ=WEEKLY",
            parentTaskID: parent.id
        )
        let grandchild = TaskItem(title: "grandchild", parentTaskID: child.id)

        for task in [parent, child, grandchild] {
            context.insert(task)
        }
        try context.save()

        try repo.cascadeComplete(parent)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let parentSpawn = try #require(tasks.first { $0.recurrenceParentId == parent.id })
        let childSpawn = try #require(tasks.first { $0.recurrenceParentId == child.id })
        #expect(tasks.count == 5)
        #expect(parent.statusRaw == TaskStatus.done.rawValue)
        #expect(child.statusRaw == TaskStatus.done.rawValue)
        #expect(grandchild.statusRaw == TaskStatus.done.rawValue)
        #expect(parentSpawn.statusRaw == TaskStatus.open.rawValue)
        #expect(parentSpawn.dueAt == stamp.addingTimeInterval(24 * 60 * 60))
        #expect(childSpawn.statusRaw == TaskStatus.open.rawValue)
        #expect(childSpawn.dueAt == childDueAt.addingTimeInterval(7 * 24 * 60 * 60))
    }

    @MainActor
    @Test("cascadeComplete keeps cancel schedule and snapshot hooks", .timeLimit(.minutes(1)))
    func cascadeCompleteKeepsLifecycleHooks() async throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let notificationRecorder = SubtaskNotificationRecorder()
        let pusherRecorder = SubtaskPusherRecorder()
        let pusher: WatchSnapshotPusher = { await pusherRecorder.bump() }
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { stamp },
            notifications: RecordingSubtaskNotificationScheduler(recorder: notificationRecorder),
            snapshotPusher: pusher
        )
        let parent = TaskItem(title: "parent", dueAt: stamp, recurrenceRule: "FREQ=DAILY")
        let child = TaskItem(title: "child", parentTaskID: parent.id)

        context.insert(parent)
        context.insert(child)
        try context.save()

        try repo.cascadeComplete(parent)

        let canceledIDs = await notificationRecorder.waitForCanceledIDs(Set([parent.id, child.id]))
        let scheduledIDs = await notificationRecorder.waitForScheduledCount(1)
        let pushCount = await pusherRecorder.waitForCount(1)
        let spawnID = try #require(
            try context.fetch(FetchDescriptor<TaskItem>())
                .first { $0.recurrenceParentId == parent.id }?.id
        )
        #expect(canceledIDs == Set([parent.id, child.id]))
        #expect(scheduledIDs == [spawnID])
        #expect(pushCount == 1)
    }

    @MainActor
    @Test("softDelete cascades by default")
    func softDeleteCascadesByDefault() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentTaskID: parent.id)
        let grandchild = TaskItem(title: "grandchild", parentTaskID: child.id)
        let otherRoot = TaskItem(title: "other root")

        for task in [parent, child, grandchild, otherRoot] {
            context.insert(task)
        }
        try context.save()

        try repo.softDelete(parent)

        for task in [parent, child, grandchild] {
            #expect(task.deletedAt == stamp)
            #expect(task.updatedAt == stamp)
        }
        #expect(otherRoot.deletedAt == nil)
    }

    @MainActor
    @Test("softDelete can skip cascading descendants")
    func softDeleteCanSkipCascade() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentTaskID: parent.id)

        context.insert(parent)
        context.insert(child)
        try context.save()

        try repo.softDelete(parent, cascade: false)

        #expect(parent.deletedAt == stamp)
        #expect(child.deletedAt == nil)
    }

    @MainActor
    @Test("softDelete cascade tolerates cyclic parent pointers")
    func softDeleteCascadeToleratesCycles() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentTaskID: parent.id)
        parent.parentTaskID = child.id

        context.insert(parent)
        context.insert(child)
        try context.save()

        try repo.softDelete(parent)

        #expect(parent.deletedAt == stamp)
        #expect(child.deletedAt == stamp)
    }

    @MainActor
    @Test("softDelete keeps cancel notification and snapshot hooks", .timeLimit(.minutes(1)))
    func softDeleteKeepsLifecycleHooks() async throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let notificationRecorder = SubtaskNotificationRecorder()
        let pusherRecorder = SubtaskPusherRecorder()
        let pusher: WatchSnapshotPusher = { await pusherRecorder.bump() }
        let repo = TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { stamp },
            notifications: RecordingSubtaskNotificationScheduler(recorder: notificationRecorder),
            snapshotPusher: pusher
        )
        let parent = TaskItem(title: "parent")
        let child = TaskItem(title: "child", parentTaskID: parent.id)

        context.insert(parent)
        context.insert(child)
        try context.save()

        try repo.softDelete(parent)

        let canceledIDs = await notificationRecorder.waitForCanceledIDs(Set([parent.id, child.id]))
        let pushCount = await pusherRecorder.waitForCount(1)
        #expect(canceledIDs == Set([parent.id, child.id]))
        #expect(pushCount == 1)
    }
}
