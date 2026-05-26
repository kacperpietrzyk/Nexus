import Foundation
import NexusCore
import Testing
@preconcurrency import UserNotifications
import os

@testable import NexusWatch

/// Recording fake conforming to `NotificationDelivering`. Mirrors the
/// iPhone-side recording centers used in `NotificationSchedulerTests` but
/// lives in the Watch test target so the scheduler can be exercised without
/// touching the real `UNUserNotificationCenter`.
private final class RecordingDelivery: NotificationDelivering, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    struct State {
        var added: [UNNotificationRequest] = []
        var removedIds: [String] = []
        var clearedAll = false
    }

    var added: [UNNotificationRequest] { lock.withLock { $0.added } }
    var removedIds: [String] { lock.withLock { $0.removedIds } }
    var clearedAll: Bool { lock.withLock { $0.clearedAll } }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock { $0.added.append(request) }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        lock.withLock { $0.removedIds.append(contentsOf: identifiers) }
    }

    func removeAllPendingNotificationRequests() async {
        lock.withLock {
            $0.clearedAll = true
            $0.added.removeAll()
        }
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

@Suite("WatchNotificationScheduler")
@MainActor
struct WatchNotificationSchedulerTests {

    @Test func install_adds_one_request_per_entry() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            NotificationSnapshotEntry(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "A",
                dueAt: now.addingTimeInterval(3_600),
                projectName: nil,
                snoozedUntil: nil
            ),
            NotificationSnapshotEntry(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                title: "B",
                dueAt: now.addingTimeInterval(7_200),
                projectName: nil,
                snoozedUntil: nil
            ),
        ]
        let snapshot = NotificationSnapshot(
            entries: entries,
            generatedAt: now,
            horizon: 24 * 3600
        )
        try await scheduler.install(snapshot: snapshot, quietHours: nil)

        #expect(delivery.added.count == 2)
        #expect(
            Set(delivery.added.map(\.identifier)) == [
                "task-11111111-1111-1111-1111-111111111111",
                "task-22222222-2222-2222-2222-222222222222",
            ]
        )
    }

    @Test func uninstallAll_clears_pending() async {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        await scheduler.uninstallAll()
        #expect(delivery.clearedAll == true)
    }

    @Test func quiet_hours_defer_trigger_to_next_active() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        let now = ISO8601DateFormatter().date(from: "2025-01-15T23:00:00Z")!
        let entry = NotificationSnapshotEntry(
            id: UUID(),
            title: "x",
            dueAt: now.addingTimeInterval(60),
            projectName: nil,
            snoozedUntil: nil
        )
        let quiet = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        try await scheduler.install(
            snapshot: NotificationSnapshot(entries: [entry], generatedAt: now, horizon: 86_400),
            quietHours: quiet
        )
        let request = try #require(delivery.added.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 7)
        #expect(trigger.dateComponents.minute == 0)
    }

    @Test func scheduleSnooze_uses_until_date_not_effectiveTriggerAt() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = NotificationSnapshotEntry(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "x",
            dueAt: now.addingTimeInterval(60),  // would be the trigger if not snoozed
            projectName: nil,
            snoozedUntil: nil
        )
        let until = now.addingTimeInterval(3_600)
        try await scheduler.scheduleSnooze(entry: entry, until: until, quietHours: nil)

        let request = try #require(delivery.added.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        let cal = Calendar.iso8601GMT
        let untilComps = cal.dateComponents([.hour, .minute], from: until)
        #expect(trigger.dateComponents.hour == untilComps.hour)
        #expect(trigger.dateComponents.minute == untilComps.minute)
    }

    @Test func scheduleSnooze_cancels_existing_pending_first() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        let id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let entry = NotificationSnapshotEntry(
            id: id, title: "x", dueAt: Date(),
            projectName: nil, snoozedUntil: nil
        )
        try await scheduler.scheduleSnooze(
            entry: entry, until: Date().addingTimeInterval(3_600), quietHours: nil
        )
        #expect(delivery.removedIds.contains("task-\(id.uuidString)"))
    }

    @Test func scheduleSnooze_respects_quiet_hours() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        let now = ISO8601DateFormatter().date(from: "2025-01-15T20:00:00Z")!
        let entry = NotificationSnapshotEntry(
            id: UUID(), title: "x", dueAt: now,
            projectName: nil, snoozedUntil: nil
        )
        let untilInsideQuietHours = ISO8601DateFormatter().date(from: "2025-01-15T23:00:00Z")!
        let quiet = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        try await scheduler.scheduleSnooze(entry: entry, until: untilInsideQuietHours, quietHours: quiet)
        let request = try #require(delivery.added.first)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.hour == 7)
        #expect(trigger.dateComponents.minute == 0)
    }

    @Test func scheduleSnooze_propagates_projectName_to_subtitle() async throws {
        let delivery = RecordingDelivery()
        let scheduler = WatchNotificationScheduler(delivery: delivery, calendar: .iso8601GMT)
        let entry = NotificationSnapshotEntry(
            id: UUID(), title: "Task title", dueAt: Date(),
            projectName: "ProjectX", snoozedUntil: nil
        )
        try await scheduler.scheduleSnooze(
            entry: entry, until: Date().addingTimeInterval(3_600), quietHours: nil
        )
        let request = try #require(delivery.added.first)
        #expect(request.content.subtitle == "ProjectX")
        #expect(request.content.title == "Task title")
    }
}

extension Calendar {
    static var iso8601GMT: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }
}
