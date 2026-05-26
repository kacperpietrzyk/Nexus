import Foundation
import NexusCore
import Testing
@preconcurrency import UserNotifications
import os

@testable import TasksFeature

/// Sendable snapshot extracted from a `UNNotificationRequest` so we can hand
/// it across isolation boundaries in tests. `UNNotificationRequest` itself
/// is not `Sendable`.
private struct RequestSnapshot: Sendable {
    let identifier: String
    let triggerHour: Int?
    let triggerMinute: Int?
    let triggerRepeats: Bool
    let isCalendarTrigger: Bool
}

/// Recording fake. The `NotificationDelivering` protocol exposes
/// non-Sendable `UNNotification*` parameters/returns, so an `actor` cannot
/// conform (actor-isolated impls require Sendable across the hop). We use a
/// `final class` + `OSAllocatedUnfairLock` to serialize state, matching the
/// pattern adopted by `RecordingNotificationCenter` in
/// `NotificationSchedulerTests`.
private final class RecorderCenter: NotificationDelivering {
    private let state = OSAllocatedUnfairLock(initialState: RecorderState())

    func add(_ request: UNNotificationRequest) async throws {
        state.withLock { $0.addedRequests.append(request) }
    }
    func removePendingNotificationRequests(withIdentifiers _: [String]) async {}
    func removeAllPendingNotificationRequests() async {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        state.withLock { $0.addedRequests }
    }
    func setNotificationCategories(_: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in this suite")
    }

    func snapshots() -> [RequestSnapshot] {
        state.withLock { state in
            state.addedRequests.map { request in
                let trigger = request.trigger as? UNCalendarNotificationTrigger
                return RequestSnapshot(
                    identifier: request.identifier,
                    triggerHour: trigger?.dateComponents.hour,
                    triggerMinute: trigger?.dateComponents.minute,
                    triggerRepeats: trigger?.repeats ?? false,
                    isCalendarTrigger: trigger != nil
                )
            }
        }
    }
}

private struct RecorderState {
    var addedRequests: [UNNotificationRequest] = []
}

@Suite("OverdueDigestScheduler")
struct OverdueDigestSchedulerTests {

    @Test("registers a daily 9:00 trigger keyed overdue-digest-daily")
    func dailyTrigger() async throws {
        let center = RecorderCenter()
        let scheduler = OverdueDigestScheduler(delivery: center)
        try await scheduler.registerDailyDigest()
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == "overdue-digest-daily")
        #expect(pending[0].isCalendarTrigger)
        #expect(pending[0].triggerRepeats == true)
        #expect(pending[0].triggerHour == 9)
        #expect(pending[0].triggerMinute == 0)
    }
}
