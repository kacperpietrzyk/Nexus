import Foundation
import NexusCore
import Observation
import UserNotifications

/// Tracks `UNAuthorizationStatus` for task reminder notifications. Exposed as
/// an `@Observable` reference type so SwiftUI views (e.g. Settings → Tasks
/// section) can re-render the denied banner reactively. The composition root
/// constructs one instance, calls `refresh()` on launch, and may call
/// `requestIfNeeded()` on first user-visible notification action.
///
/// Wraps a `NotificationDelivering` for testability — production apps default
/// to `SystemNotificationCenter`.
@MainActor
@Observable
public final class NotificationPermissionState {
    public private(set) var status: UNAuthorizationStatus = .notDetermined

    private let delivery: any NotificationDelivering

    public init(delivery: any NotificationDelivering = SystemNotificationCenter()) {
        self.delivery = delivery
    }

    /// Reads the current authorization status from the system. Idempotent —
    /// safe to call on every launch and after returning from foreground.
    public func refresh() async {
        let settings = await delivery.notificationSettings()
        self.status = settings.authorizationStatus
    }

    /// First-run prompt. No-op if status is already determined (granted,
    /// denied, provisional, or ephemeral). Re-reads settings after the
    /// prompt resolves so observers see the final state.
    public func requestIfNeeded() async {
        guard status == .notDetermined else { return }
        do {
            _ = try await delivery.requestAuthorization(
                options: [.alert, .badge, .sound, .provisional]
            )
            await refresh()
        } catch {
            await refresh()
        }
    }
}
