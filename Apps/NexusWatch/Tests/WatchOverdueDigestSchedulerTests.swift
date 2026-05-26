import Foundation
import NexusCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
import os

@testable import NexusWatch

private final class CapturingDelivery: NotificationDelivering, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var added: [UNNotificationRequest] = []
        var removedIds: [String] = []
    }

    var added: [UNNotificationRequest] { lock.withLock { $0.added } }
    var removedIds: [String] { lock.withLock { $0.removedIds } }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { $0.added.append(request) }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        lock.withLock { $0.removedIds.append(contentsOf: identifiers) }
    }

    func removeAllPendingNotificationRequests() async {
        lock.withLock { $0.added.removeAll() }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { $0.added }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {}

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }

    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in these tests")
    }
}

private final class FakeFreshness: WatchIPhonePresenceProbing, @unchecked Sendable {
    let lastIPhonePing: Date?

    init(lastPing: Date?) {
        self.lastIPhonePing = lastPing
    }
}

@Suite("WatchOverdueDigestScheduler")
@MainActor
struct WatchOverdueDigestSchedulerTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        return ModelContext(container)
    }

    @Test func reschedules_with_overdue_count_when_iphone_offline() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        for offset in [25 * 3_600.0, 26 * 3_600.0, 27 * 3_600.0] {
            let task = TaskItem(title: "x", dueAt: now.addingTimeInterval(-offset))
            context.insert(task)
        }
        let delivery = CapturingDelivery()
        let probe = FakeFreshness(lastPing: nil)
        let scheduler = WatchOverdueDigestScheduler(
            context: context,
            delivery: delivery,
            presenceProbe: probe,
            calendar: .iso8601GMT,
            now: { now }
        )

        await scheduler.refreshAndSchedule()

        #expect(delivery.added.count == 1)
        #expect(delivery.added.first?.content.body == "3 zaległe zadania")
        #expect(delivery.removedIds.contains("digest-overdue") == true)
    }

    @Test func digest_count_ignores_tasks_due_earlier_today() async throws {
        let now = Date(timeIntervalSince1970: 1_800_003_600)
        let context = try makeContext()
        context.insert(TaskItem(title: "yesterday", dueAt: now.addingTimeInterval(-25 * 3_600)))
        context.insert(TaskItem(title: "earlier today", dueAt: now.addingTimeInterval(-30 * 60)))
        let delivery = CapturingDelivery()
        let probe = FakeFreshness(lastPing: nil)
        let scheduler = WatchOverdueDigestScheduler(
            context: context,
            delivery: delivery,
            presenceProbe: probe,
            calendar: .iso8601GMT,
            now: { now }
        )

        await scheduler.refreshAndSchedule()

        #expect(delivery.added.first?.content.body == "1 zaległe zadanie")
    }

    @Test func skips_when_iphone_was_reachable_late_yesterday() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let context = try makeContext()
        let delivery = CapturingDelivery()
        let probe = FakeFreshness(lastPing: now.addingTimeInterval(-3 * 3_600))
        let scheduler = WatchOverdueDigestScheduler(
            context: context,
            delivery: delivery,
            presenceProbe: probe,
            calendar: .iso8601GMT,
            now: { now }
        )

        await scheduler.refreshAndSchedule()

        #expect(delivery.added.isEmpty)
        #expect(delivery.removedIds.contains("digest-overdue") == true)
    }
}
