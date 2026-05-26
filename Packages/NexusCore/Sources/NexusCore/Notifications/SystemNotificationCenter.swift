import Foundation
import UserNotifications

/// Production conformance — wraps `UNUserNotificationCenter.current()`.
public struct SystemNotificationCenter: NotificationDelivering {
    public init() {}

    public func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPendingNotificationRequests() async {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    public func notificationSettings() async -> UNNotificationSettings {
        await UNUserNotificationCenter.current().notificationSettings()
    }
}
