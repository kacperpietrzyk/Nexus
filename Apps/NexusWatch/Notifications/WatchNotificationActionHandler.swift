import Foundation
import NexusCore
import OSLog
import SwiftData
import UserNotifications

#if canImport(WatchKit)
import WatchKit
#endif

/// Routes the five notification actions on the Watch (`DONE`, `SNOOZE_15M`,
/// `SNOOZE_1H`, `SNOOZE_TOMORROW`, `SNOOZE_CUSTOM`). Each action mutates the
/// local App Group SwiftData store, re-arms the Watch's
/// `WatchNotificationScheduler` for snooze cases, and forwards the canonical
/// payload to the iPhone for repository reconciliation. Custom snooze opens
/// `nexus://task/<id>/snooze` for the URL handler in `WatchRootView`.
@MainActor
final class WatchNotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "WatchNotifAction"
    )

    private let context: ModelContext
    private let bridge: any WatchActionSending
    private let scheduler: WatchNotificationScheduler
    private let quietHoursStore: (any QuietHoursLoading)?
    private let nowProvider: @Sendable () -> Date

    init(
        context: ModelContext,
        bridge: any WatchActionSending,
        scheduler: WatchNotificationScheduler,
        quietHoursStore: (any QuietHoursLoading)?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.bridge = bridge
        self.scheduler = scheduler
        self.quietHoursStore = quietHoursStore
        self.nowProvider = now
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let idString = response.notification.request.content.userInfo["taskId"] as? String
        let actionID = response.actionIdentifier
        guard let idString, let id = UUID(uuidString: idString) else {
            completionHandler()
            return
        }
        _Concurrency.Task { @MainActor [self] in
            await self.handle(actionID: actionID, taskID: id)
            completionHandler()
        }
    }

    /// Used by `WatchCustomSnoozeView` after the user picks a custom date.
    /// Bypasses the action-ID switch since this isn't a notification action.
    func snoozeCustom(taskID: UUID, until: Date) async {
        await performSnooze(taskID: taskID, until: until)
    }

    func handle(actionID: String, taskID: UUID) async {
        switch actionID {
        case NotificationActionID.done.rawValue:
            performDone(taskID: taskID)
        case NotificationActionID.snooze15M.rawValue:
            await performSnooze(taskID: taskID, by: 15 * 60)
        case NotificationActionID.snooze1H.rawValue:
            await performSnooze(taskID: taskID, by: 60 * 60)
        case NotificationActionID.snoozeTomorrow.rawValue:
            await performSnooze(taskID: taskID, until: nextMorningNine(after: nowProvider()))
        case NotificationActionID.snoozeCustom.rawValue:
            openCustomSnoozeURL(for: taskID)
        default:
            break
        }
    }

    private func fetchTask(id: UUID) -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    private func performDone(taskID: UUID) {
        guard let task = fetchTask(id: taskID) else { return }
        guard !(task.statusRaw == TaskStatus.done.rawValue && task.lastCompletedAt != nil) else {
            return
        }
        let stamp = nowProvider()
        task.statusRaw = TaskStatus.done.rawValue
        task.lastCompletedAt = stamp
        task.updatedAt = stamp
        do {
            try context.save()
        } catch {
            Self.logger.error(
                "done save failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        let id = task.id
        let bridge = self.bridge
        _Concurrency.Task { @MainActor in
            do {
                try await bridge.sendMarkDone(taskID: id)
            } catch {
                Self.logger.error(
                    "done bridge failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func performSnooze(taskID: UUID, by interval: TimeInterval) async {
        await performSnooze(taskID: taskID, until: nowProvider().addingTimeInterval(interval))
    }

    private func performSnooze(taskID: UUID, until: Date) async {
        guard let task = fetchTask(id: taskID) else { return }
        task.statusRaw = TaskStatus.snoozed.rawValue
        task.snoozedUntil = until
        task.updatedAt = nowProvider()
        do {
            try context.save()
        } catch {
            Self.logger.error(
                "snooze save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        let entry = NotificationSnapshotEntry(
            id: task.id,
            title: task.title,
            dueAt: task.dueAt ?? until,
            projectName: nil,
            snoozedUntil: until
        )
        do {
            try await scheduler.scheduleSnooze(
                entry: entry,
                until: until,
                quietHours: quietHoursStore?.load()
            )
        } catch {
            Self.logger.error(
                "snooze reschedule failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        do {
            try await bridge.sendSnoozeAction(taskID: task.id, until: until)
        } catch {
            Self.logger.error(
                "snooze bridge failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func openCustomSnoozeURL(for id: UUID) {
        guard let url = URL(string: "nexus://task/\(id.uuidString)/snooze") else { return }
        #if canImport(WatchKit)
        WKExtension.shared().openSystemURL(url)
        #endif
    }

    private func nextMorningNine(after date: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
