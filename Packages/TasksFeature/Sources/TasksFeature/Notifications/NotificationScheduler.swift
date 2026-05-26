import Foundation
import NexusCore
import UserNotifications

/// Owns the per-`TaskItem` notification lifecycle. Identifiers are stable
/// (`task-<uuid>`) so cancel + reschedule works without lookup.
///
/// `@MainActor` matches the SwiftData isolation already used by
/// `TaskItemRepository`: `TaskItem` is a non-`Sendable` `@Model` type, so the
/// scheduler runs on the same isolation as its caller and avoids cross-actor
/// hops with the model object. Quiet-hours integration: if `dueAt` falls
/// inside the quiet window, the trigger is deferred to
/// `QuietHours.nextActive(after:)`.
@MainActor
public final class NotificationScheduler {
    private let delivery: any NotificationDelivering
    private let quietHoursProvider: @Sendable () -> QuietHours?
    private let calendar: Calendar

    public init(
        delivery: any NotificationDelivering,
        quietHours: @escaping @Sendable () -> QuietHours?,
        calendar: Calendar = .current
    ) {
        self.delivery = delivery
        self.quietHoursProvider = quietHours
        self.calendar = calendar
    }

    /// Adds a `UNNotificationRequest` for an open, non-deleted task with a
    /// `dueAt`. No-op for tasks without `dueAt` or for done/deleted tasks.
    /// If `dueAt` falls inside the configured quiet window, the trigger is
    /// deferred to `QuietHours.nextActive(after:)`.
    public func schedule(_ task: TaskItem) async throws {
        guard task.status == .open, task.deletedAt == nil, let due = task.dueAt else { return }
        let triggerDate = quietHoursProvider()?.nextActive(after: due, calendar: calendar) ?? due

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger
        )
        try await delivery.add(request)
    }

    /// Removes the pending request keyed `task-<uuid>`.
    public func cancel(taskID: UUID) async {
        await delivery.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: taskID)]
        )
    }

    /// Cancel + schedule. Use after edits that may change `dueAt` or status.
    public func reschedule(_ task: TaskItem) async throws {
        await cancel(taskID: task.id)
        try await schedule(task)
    }

    /// Cancels any pending request for this task and schedules a fresh one
    /// firing at `until`. Bypasses the `.open` status check used by `schedule`,
    /// since the snooze flow flips status to `.snoozed` immediately. Quiet hours
    /// still apply: if `until` falls inside the quiet window, defer to nextActive.
    public func scheduleSnooze(_ task: TaskItem, until: Date) async throws {
        await cancel(taskID: task.id)
        guard task.deletedAt == nil else { return }
        let triggerDate = quietHoursProvider()?.nextActive(after: until, calendar: calendar) ?? until

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger
        )
        try await delivery.add(request)
    }

    private func identifier(for id: UUID) -> String { "task-\(id.uuidString)" }
}
