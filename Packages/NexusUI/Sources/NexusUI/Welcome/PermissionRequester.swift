import Foundation

#if !os(watchOS)
import UserNotifications

/// Async helper invoked when the user finishes the welcome flow.
public enum PermissionRequester {
    /// Request all welcome-flow permissions in order. Denials and errors do not block launch.
    @MainActor
    public static func requestAll() async {
        await requestNotifications()
        // Apple Intelligence consent remains owned by the existing AI settings/first-use flow.
    }

    @MainActor
    private static func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("PermissionRequester: notifications request failed - \(error)")
        }
    }
}

#endif
