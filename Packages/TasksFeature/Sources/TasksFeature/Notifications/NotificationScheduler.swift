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
    private let now: @Sendable () -> Date

    /// How soon an overdue reminder fires after it is (re)scheduled. A
    /// non-repeating `UNCalendarNotificationTrigger` whose matched date is in
    /// the past never fires, so for an already-passed due date we fall back to
    /// a short time-interval trigger instead of a dead request.
    nonisolated private static let overdueReminderDelay: TimeInterval = 5

    public init(
        delivery: any NotificationDelivering,
        quietHours: @escaping @Sendable () -> QuietHours?,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.delivery = delivery
        self.quietHoursProvider = quietHours
        self.calendar = calendar
        self.now = now
    }

    /// Adds `UNNotificationRequest`s for an open, non-deleted task.
    /// When `reminders` is non-empty, schedules one request per rule keyed
    /// `task-<uuid>-r<index>`. Falls back to the legacy single `task-<uuid>`
    /// request (from `dueAt`) when `reminders` is empty.
    /// If a fire date falls inside the configured quiet window, the trigger is
    /// deferred to `QuietHours.nextActive(after:)`.
    public func schedule(_ task: TaskItem) async throws {
        guard task.status == .open, task.deletedAt == nil else { return }

        let rules = task.reminders
        guard !rules.isEmpty else {
            try await scheduleLegacyDueReminder(task)
            return
        }

        let currentDate = now()
        for (index, rule) in rules.enumerated() {
            guard let fireDate = resolve(rule, for: task) else { continue }
            guard fireDate > currentDate else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
            content.userInfo = ["taskId": task.id.uuidString]
            let request = UNNotificationRequest(
                identifier: "\(identifier(for: task.id))-r\(index)",
                content: content,
                trigger: trigger(firingAt: fireDate)
            )
            try await delivery.add(request)
        }
    }

    /// Removes all pending requests for the given task: the legacy single id
    /// `task-<uuid>` plus per-reminder ids `task-<uuid>-r0…r31`.
    /// Removing non-existent identifiers is a no-op in UserNotifications.
    public func cancel(taskID: UUID) async {
        let base = identifier(for: taskID)
        var ids = [base] + (0..<32).map { "\(base)-r\($0)" }
        let pendingIDs = await delivery.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0 == base || $0.hasPrefix("\(base)-r") }
        for id in pendingIDs where !ids.contains(id) {
            ids.append(id)
        }
        await delivery.removePendingNotificationRequests(withIdentifiers: ids)
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

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]

        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger(firingAt: until)
        )
        try await delivery.add(request)
    }

    /// Pre-reminders behavior: a single request keyed `task-<uuid>` fired at `dueAt`.
    private func scheduleLegacyDueReminder(_ task: TaskItem) async throws {
        guard let due = task.dueAt else { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = ["taskId": task.id.uuidString]
        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger(firingAt: due)
        )
        try await delivery.add(request)
    }

    /// Resolves a reminder rule to a concrete fire date, or nil if unresolvable
    /// (relative rule whose anchor date is not set).
    private func resolve(_ rule: ReminderRule, for task: TaskItem) -> Date? {
        switch rule {
        case .absolute(let date):
            return date
        case .relative(let offset, let anchor):
            let base: Date? = (anchor == .due) ? task.dueAt : task.deadlineAt
            return base.map { $0.addingTimeInterval(offset) }
        }
    }

    /// Builds the trigger for a requested fire date, applying quiet hours.
    /// Future dates use a calendar trigger (as before). A date that has already
    /// passed — e.g. an overdue task's `dueAt` — would make a non-repeating
    /// calendar trigger dead, so it falls back to a short time-interval trigger
    /// that fires soon, still deferring out of an active quiet window.
    nonisolated private func trigger(firingAt requested: Date) -> UNNotificationTrigger {
        let currentDate = now()
        let target = quietHoursProvider()?.nextActive(after: requested, calendar: calendar) ?? requested
        if target > currentDate {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: target)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }
        let soon = currentDate.addingTimeInterval(Self.overdueReminderDelay)
        let deferred = quietHoursProvider()?.nextActive(after: soon, calendar: calendar) ?? soon
        let interval = max(Self.overdueReminderDelay, deferred.timeIntervalSince(currentDate))
        return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    }

    private func identifier(for id: UUID) -> String { "task-\(id.uuidString)" }
}
