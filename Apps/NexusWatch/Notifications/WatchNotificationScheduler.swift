import Foundation
import NexusCore
import UserNotifications

/// Watch-side scheduler that mirrors the iPhone `NotificationScheduler` API
/// but operates on `NotificationSnapshotEntry` instead of `TaskItem` -- the
/// Watch deliberately does not take a SwiftData write dependency for trigger
/// semantics. Identifiers are stable (`task-<uuid>`) and identical to the
/// iPhone scheme so logs and debugging stay consistent across devices.
@MainActor
final class WatchNotificationScheduler {
    private let delivery: any NotificationDelivering
    private let calendar: Calendar

    init(delivery: any NotificationDelivering, calendar: Calendar = .current) {
        self.delivery = delivery
        self.calendar = calendar
    }

    /// Replaces all pending Watch reminders with one request per snapshot
    /// entry. Quiet-hours deferral is applied per-entry via
    /// `QuietHours.nextActive(after:)`.
    func install(snapshot: NotificationSnapshot, quietHours: QuietHours?) async throws {
        await uninstallAll()
        for entry in snapshot.entries {
            try await schedule(entry: entry, quietHours: quietHours)
        }
    }

    /// Schedules a single entry. Trigger is computed from
    /// `entry.effectiveTriggerAt` (snooze release time when present, else
    /// `dueAt`). When quiet hours contain the trigger, defers to nextActive.
    func schedule(entry: NotificationSnapshotEntry, quietHours: QuietHours?) async throws {
        let triggerDate =
            quietHours?
            .nextActive(after: entry.effectiveTriggerAt, calendar: calendar)
            ?? entry.effectiveTriggerAt

        let content = makeContent(for: entry)

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: entry.id),
            content: content,
            trigger: trigger
        )
        try await delivery.add(request)
    }

    /// Cancels any pending request for this entry and schedules a fresh one
    /// firing at `until`. Mirrors `NotificationScheduler.scheduleSnooze` --
    /// quiet hours still apply.
    func scheduleSnooze(
        entry: NotificationSnapshotEntry,
        until: Date,
        quietHours: QuietHours?
    ) async throws {
        await delivery.removePendingNotificationRequests(
            withIdentifiers: [identifier(for: entry.id)]
        )
        let triggerDate = quietHours?.nextActive(after: until, calendar: calendar) ?? until
        let content = makeContent(for: entry)

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try await delivery.add(
            UNNotificationRequest(
                identifier: identifier(for: entry.id),
                content: content,
                trigger: trigger
            )
        )
    }

    nonisolated private func makeContent(
        for entry: NotificationSnapshotEntry
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = entry.title
        content.categoryIdentifier = NotificationCategory.taskReminder.rawValue
        content.userInfo = [
            "taskId": entry.id.uuidString,
            "dueAt": entry.dueAt.timeIntervalSince1970,
        ]
        if let projectName = entry.projectName {
            content.subtitle = projectName
        }
        return content
    }

    /// Drops every pending Watch *task* reminder owned by this scheduler. Used before
    /// re-installing from a fresh snapshot and as a hard reset.
    ///
    /// Only `task-<uuid>` identifiers are removed — NOT every pending request. Using
    /// `removeAllPendingNotificationRequests()` here also wiped sibling requests such as
    /// `WatchOverdueDigestScheduler`'s `digest-overdue`, which is scheduled moments earlier on
    /// launch, silently erasing the morning overdue digest exactly when the Watch is the local
    /// master (iPhone unreachable).
    func uninstallAll() async {
        let ownedIdentifiers = await delivery.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.taskIdentifierPrefix) }
        guard !ownedIdentifiers.isEmpty else { return }
        await delivery.removePendingNotificationRequests(withIdentifiers: ownedIdentifiers)
    }

    private static let taskIdentifierPrefix = "task-"
    private func identifier(for id: UUID) -> String { "\(Self.taskIdentifierPrefix)\(id.uuidString)" }
}
