import Foundation
import NexusCore
import Testing
@preconcurrency import UserNotifications
import os

@testable import NexusWatch

private final class FakeProbe: WatchReachabilityProbing, @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<State>

    struct State {
        var reachable: Bool
        var lastPing: Date?
    }

    init(reachable: Bool, lastPing: Date?) {
        self.lock = OSAllocatedUnfairLock(
            initialState: State(reachable: reachable, lastPing: lastPing)
        )
    }

    var isReachable: Bool { lock.withLock { $0.reachable } }
    var lastIPhonePing: Date? { lock.withLock { $0.lastPing } }

    func setReachable(_ value: Bool) { lock.withLock { $0.reachable = value } }
    func bumpPing(_ value: Date) { lock.withLock { $0.lastPing = value } }
}

private final class CountingDelivery: NotificationDelivering, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var addCount = 0
        var clearAllCount = 0
    }

    var addCount: Int { lock.withLock { $0.addCount } }
    var clearAllCount: Int { lock.withLock { $0.clearAllCount } }

    func add(_: UNNotificationRequest) async throws { lock.withLock { $0.addCount += 1 } }
    func removePendingNotificationRequests(withIdentifiers _: [String]) async {}
    func removeAllPendingNotificationRequests() async { lock.withLock { $0.clearAllCount += 1 } }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func setNotificationCategories(_: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in these tests")
    }
}

private final class FailingDelivery: NotificationDelivering, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var addCount: Int { lock.withLock { $0 } }

    func add(_: UNNotificationRequest) async throws {
        lock.withLock { $0 += 1 }
        throw NSError(domain: "WatchNotificationGuardTests", code: 1)
    }

    func removePendingNotificationRequests(withIdentifiers _: [String]) async {}
    func removeAllPendingNotificationRequests() async {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func setNotificationCategories(_: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in these tests")
    }
}

private final class InMemorySnapshotStore: WatchSnapshotLoading, @unchecked Sendable {
    private let snapshot: NotificationSnapshot?
    init(snapshot: NotificationSnapshot?) { self.snapshot = snapshot }
    func load() -> NotificationSnapshot? { snapshot }
}

private final class InMemoryQuietHoursStore: QuietHoursLoading, @unchecked Sendable {
    func load() -> QuietHours? { nil }
}

private func sampleSnapshot(now: Date) -> NotificationSnapshot {
    NotificationSnapshot(
        entries: [
            NotificationSnapshotEntry(
                id: UUID(),
                title: "x",
                dueAt: now.addingTimeInterval(3_600),
                projectName: nil,
                snoozedUntil: nil
            )
        ],
        generatedAt: now,
        horizon: 86_400
    )
}

@Suite("WatchNotificationGuard")
@MainActor
struct WatchNotificationGuardTests {

    @Test func reachable_with_recent_ping_uninstalls() async throws {
        let now = Date()
        let probe = FakeProbe(reachable: true, lastPing: now.addingTimeInterval(-10))
        let delivery = CountingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery)
        let store = InMemorySnapshotStore(snapshot: sampleSnapshot(now: now))
        let guardObj = WatchNotificationGuard(
            snapshotStore: store,
            scheduler: scheduler,
            probe: probe,
            quietHoursStore: InMemoryQuietHoursStore(),
            now: { now }
        )
        await guardObj.evaluate()
        #expect(delivery.clearAllCount >= 1)
        #expect(delivery.addCount == 0)
    }

    @Test func unreachable_with_stale_ping_installs() async throws {
        let now = Date()
        let probe = FakeProbe(reachable: false, lastPing: now.addingTimeInterval(-200))
        let delivery = CountingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery)
        let store = InMemorySnapshotStore(snapshot: sampleSnapshot(now: now))
        let guardObj = WatchNotificationGuard(
            snapshotStore: store,
            scheduler: scheduler,
            probe: probe,
            quietHoursStore: InMemoryQuietHoursStore(),
            now: { now }
        )
        await guardObj.evaluate()
        #expect(delivery.addCount == 1)
    }

    @Test func unreachable_with_recent_ping_is_debounced_and_schedules_followup() async throws {
        let now = Date()
        let probe = FakeProbe(reachable: false, lastPing: now.addingTimeInterval(-30))
        let delivery = CountingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery)
        let store = InMemorySnapshotStore(snapshot: sampleSnapshot(now: now))
        let guardObj = WatchNotificationGuard(
            snapshotStore: store,
            scheduler: scheduler,
            probe: probe,
            quietHoursStore: InMemoryQuietHoursStore(),
            now: { now }
        )
        await guardObj.evaluate()
        #expect(delivery.addCount == 0)
        #expect(guardObj.hasPendingDelayedEvaluation == true)
    }

    @Test func failed_install_is_retried_for_same_snapshot() async throws {
        let now = Date()
        let probe = FakeProbe(reachable: false, lastPing: now.addingTimeInterval(-200))
        let delivery = FailingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery)
        let store = InMemorySnapshotStore(snapshot: sampleSnapshot(now: now))
        let guardObj = WatchNotificationGuard(
            snapshotStore: store,
            scheduler: scheduler,
            probe: probe,
            quietHoursStore: InMemoryQuietHoursStore(),
            now: { now }
        )

        await guardObj.evaluate()
        await guardObj.evaluate()

        #expect(delivery.addCount == 2)
    }
}
