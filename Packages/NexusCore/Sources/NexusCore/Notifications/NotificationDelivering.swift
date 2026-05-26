import Foundation
import UserNotifications

/// Subset of `UNUserNotificationCenter` we depend on. Lets `NotificationScheduler`
/// be tested with a recording fake.
public protocol NotificationDelivering: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeAllPendingNotificationRequests() async
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func notificationSettings() async -> UNNotificationSettings
}
