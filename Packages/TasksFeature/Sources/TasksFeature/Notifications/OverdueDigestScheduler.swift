import Foundation
import NexusCore
import UserNotifications

/// Schedules the daily 9:00 overdue digest. The notification body is rendered
/// at delivery time by `NexusiOSDigestExtension`, which queries
/// `TodayQuery.overdue` against the shared App Group container.
public actor OverdueDigestScheduler {
    public static let identifier = "overdue-digest-daily"

    private let delivery: any NotificationDelivering

    public init(delivery: any NotificationDelivering) {
        self.delivery = delivery
    }

    public func registerDailyDigest() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Zaległe zadania"
        content.body = "Sprawdź zaległe zadania"  // overwritten by the content extension
        content.categoryIdentifier = NotificationCategory.overdueDigest.rawValue

        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: trigger
        )
        try await delivery.add(request)
    }

    public func cancel() async {
        await delivery.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
