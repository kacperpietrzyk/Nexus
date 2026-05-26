import Foundation
import UserNotifications

public enum NotificationCategory: String {
    case taskReminder = "TASK_REMINDER"
    case overdueDigest = "OVERDUE_DIGEST"
    /// Informational Watch Ask Nexus reply. No custom actions are registered.
    case watchAgentReply = "WATCH_AGENT_REPLY"
}

public enum NotificationActionID: String {
    case done = "DONE"
    case snooze15M = "SNOOZE_15M"
    case snooze1H = "SNOOZE_1H"
    case snoozeTomorrow = "SNOOZE_TOMORROW"
    case snoozeCustom = "SNOOZE_CUSTOM"
}

/// Builds and registers the `TASK_REMINDER` notification category with the
/// four snooze actions (15M / 1H / Tomorrow / Custom).
public enum NotificationCategories {
    public static func taskReminder() -> UNNotificationCategory {
        let actions: [UNNotificationAction] = [
            UNNotificationAction(
                identifier: NotificationActionID.snooze15M.rawValue,
                title: "Drzemka 15 min",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snooze1H.rawValue,
                title: "Drzemka 1 godz",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snoozeTomorrow.rawValue,
                title: "Jutro rano",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snoozeCustom.rawValue,
                title: "Wybierz…",
                options: [.foreground]
            ),
        ]
        return UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }

    /// Watch-specific variant of `taskReminder` that prepends a "Wykonane"
    /// (done) action. iPhone notifications use the body tap to open the app
    /// where Done is one click away in `TaskListView`; on the Watch the
    /// notification surface is the only UI you'll see, so we expose Done as
    /// a first-class action.
    public static func watchTaskReminder() -> UNNotificationCategory {
        let actions: [UNNotificationAction] = [
            UNNotificationAction(
                identifier: NotificationActionID.done.rawValue,
                title: "Wykonane",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snooze15M.rawValue,
                title: "Drzemka 15 min",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snooze1H.rawValue,
                title: "Drzemka 1 godz",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snoozeTomorrow.rawValue,
                title: "Jutro rano",
                options: []
            ),
            UNNotificationAction(
                identifier: NotificationActionID.snoozeCustom.rawValue,
                title: "Wybierz…",
                options: [.foreground]
            ),
        ]
        return UNNotificationCategory(
            identifier: NotificationCategory.taskReminder.rawValue,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }

    public static func registerAll(on delivery: any NotificationDelivering) async {
        await delivery.setNotificationCategories([taskReminder()])
    }

    public static func registerWatchAll(on delivery: any NotificationDelivering) async {
        await delivery.setNotificationCategories([watchTaskReminder()])
    }
}
