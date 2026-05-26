import Foundation
import NexusCore
import Testing
@preconcurrency import UserNotifications

@testable import TasksFeature

/// `NotificationPermissionState` is intentionally minimal: it stores a single
/// `UNAuthorizationStatus` and refreshes it from `UNNotificationSettings`. The
/// status-reading paths cannot be unit-tested directly because
/// `UNNotificationSettings` has no public initializer — there is no way to
/// stub a value that `notificationSettings()` could return.
///
/// We test only what is reachable without instantiating `UNNotificationSettings`:
/// the default `.notDetermined` status set by `init`. Both `refresh()` and
/// `requestIfNeeded()` ultimately call `notificationSettings()`, so they would
/// trip a `fatalError` in any reasonable fake. Coverage for those paths is
/// expected to come from manual smoke testing on device.
private final class NoOpNotificationCenter: NotificationDelivering {
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {}
    func removeAllPendingNotificationRequests() async {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("UNNotificationSettings has no public init — tests avoid this path")
    }
}

@Suite("NotificationPermissionState")
@MainActor
struct NotificationPermissionStateTests {

    @Test("init starts with status .notDetermined")
    func defaultStatusIsNotDetermined() {
        let state = NotificationPermissionState(delivery: NoOpNotificationCenter())
        #expect(state.status == .notDetermined)
    }
}
