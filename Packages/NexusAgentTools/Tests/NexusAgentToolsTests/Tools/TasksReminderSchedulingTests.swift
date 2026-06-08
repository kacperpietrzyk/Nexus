import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("Tasks reminder scheduling")
struct TasksReminderSchedulingTests {
    @MainActor
    @Test("tasks.update reminder patch reschedules notifications through repository")
    func updateReminderPatchReschedulesNotifications() async throws {
        let recorder = ReminderNotificationRecorder()
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TaskItem(title: "notify me", dueAt: dueAt)
        let fixture = try await InMemoryAgentContext.make(
            tasks: [task],
            notifications: RecordingReminderNotificationScheduler(recorder: recorder)
        )

        _ = try await TasksUpdateTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "patch": .object([
                    "reminders": .array([
                        .object([
                            "type": .string("relative"),
                            "offset": .double(-1800),
                            "anchor": .string("due"),
                        ])
                    ])
                ]),
            ]),
            context: fixture.context
        )

        let event = await recorder.waitForReschedule(taskID: task.id)
        #expect(event.reminders == [.relative(offset: -1800, anchor: .due)])
    }
}

private struct ReminderNotificationEvent: Equatable {
    let taskID: UUID
    let reminders: [ReminderRule]
}

private actor ReminderNotificationRecorder {
    private struct Waiter {
        let taskID: UUID
        let continuation: CheckedContinuation<ReminderNotificationEvent, Never>
    }

    private var events: [ReminderNotificationEvent] = []
    private var waiters: [Waiter] = []

    func recordReschedule(taskID: UUID, reminders: [ReminderRule]) {
        let event = ReminderNotificationEvent(taskID: taskID, reminders: reminders)
        events.append(event)
        resolveWaiters()
    }

    func waitForReschedule(taskID: UUID) async -> ReminderNotificationEvent {
        if let event = events.first(where: { $0.taskID == taskID }) {
            return event
        }
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(taskID: taskID, continuation: continuation))
        }
    }

    private func resolveWaiters() {
        var resumed: [Int] = []
        for (index, waiter) in waiters.enumerated() {
            guard let event = events.first(where: { $0.taskID == waiter.taskID }) else { continue }
            waiter.continuation.resume(returning: event)
            resumed.append(index)
        }
        for index in resumed.reversed() {
            waiters.remove(at: index)
        }
    }
}

private struct RecordingReminderNotificationScheduler: NotificationScheduling {
    let recorder: ReminderNotificationRecorder

    func schedule(_: TaskItem) async throws {}
    func cancel(taskID _: UUID) async {}

    func reschedule(_ task: TaskItem) async throws {
        await recorder.recordReschedule(taskID: task.id, reminders: task.reminders)
    }

    func scheduleSnooze(_: TaskItem, until _: Date) async throws {}
}
