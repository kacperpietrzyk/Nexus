import Foundation
import NexusCore
import Testing
@preconcurrency import UserNotifications
import os

@testable import TasksFeature

/// Sendable snapshot extracted from a `UNNotificationRequest` so we can
/// hand it across isolation boundaries in tests. `UNNotificationRequest`
/// itself is not `Sendable`.
private struct RequestSnapshot: Sendable {
    let identifier: String
    let title: String
    let categoryIdentifier: String
    let triggerDay: Int?
    let triggerHour: Int?
    let triggerMinute: Int?
}

/// Recording fake. The `NotificationDelivering` protocol exposes
/// non-Sendable `UNNotification*` parameters/returns, so an `actor`
/// cannot conform (actor-isolated impls require Sendable across the hop).
/// We use a `final class` + `OSAllocatedUnfairLock` to serialize state,
/// matching the async-safe locking pattern Swift 6 prefers.
private final class RecordingNotificationCenter: NotificationDelivering {
    private let state = OSAllocatedUnfairLock(initialState: RecorderState())

    func add(_ request: UNNotificationRequest) async throws {
        state.withLock { $0.addedRequests.append(request) }
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        state.withLock { $0.removedIdentifiers.append(contentsOf: identifiers) }
    }
    func removeAllPendingNotificationRequests() async {
        state.withLock { $0.addedRequests.removeAll() }
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        state.withLock { $0.addedRequests }
    }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in this suite")
    }

    /// Sendable view of the recorded requests for cross-task assertions.
    func snapshots() -> [RequestSnapshot] {
        state.withLock { state in
            state.addedRequests.map { request in
                let trigger = request.trigger as? UNCalendarNotificationTrigger
                return RequestSnapshot(
                    identifier: request.identifier,
                    title: request.content.title,
                    categoryIdentifier: request.content.categoryIdentifier,
                    triggerDay: trigger?.dateComponents.day,
                    triggerHour: trigger?.dateComponents.hour,
                    triggerMinute: trigger?.dateComponents.minute
                )
            }
        }
    }

    var removedIdentifiers: [String] {
        state.withLock { $0.removedIdentifiers }
    }
}

private struct RecorderState {
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
}

@Suite("NotificationScheduler")
@MainActor
struct NotificationSchedulerTests {

    private func cal() -> Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .gmt
        return c
    }

    @Test("schedule adds a request keyed task-<uuid>")
    func scheduleAddsRequest() async throws {
        let center = RecordingNotificationCenter()
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal()
        )
        let task = TaskItem(
            title: "Reply Magda",
            dueAt: ISO8601DateFormatter().date(from: "2026-05-06T13:00:00Z")
        )
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == "task-\(task.id.uuidString)")
        #expect(pending[0].title == "Reply Magda")
        #expect(pending[0].categoryIdentifier == NotificationCategory.taskReminder.rawValue)
    }

    @Test("schedule no-op for a task without dueAt")
    func scheduleNoOpForUndatedTask() async throws {
        let center = RecordingNotificationCenter()
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal()
        )
        try await scheduler.schedule(TaskItem(title: "no date"))
        #expect(center.snapshots().isEmpty)
    }

    @Test("schedule defers a trigger inside quiet hours to nextActive")
    func quietHoursDefersTrigger() async throws {
        let center = RecordingNotificationCenter()
        let quiet = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { quiet },
            calendar: cal()
        )
        let inQuietHours = ISO8601DateFormatter().date(from: "2026-05-05T23:00:00Z")!
        let task = TaskItem(title: "Late reminder", dueAt: inQuietHours)
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].triggerHour == 7)
        #expect(pending[0].triggerMinute == 0)
    }

    @Test("cancel removes the keyed identifier")
    func cancelRemoves() async {
        let center = RecordingNotificationCenter()
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal()
        )
        let id = UUID()
        await scheduler.cancel(taskID: id)
        #expect(center.removedIdentifiers == ["task-\(id.uuidString)"])
    }

    @Test("scheduleSnooze adds a request keyed task-<uuid> using the snooze target")
    func scheduleSnoozeUsesUntilDate() async throws {
        let center = RecordingNotificationCenter()
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal()
        )
        let snoozeTarget = ISO8601DateFormatter().date(from: "2026-05-06T09:00:00Z")!
        let task = TaskItem(title: "Snoozed task")
        // Mark as snoozed to confirm the method does not guard on .open.
        task.statusRaw = TaskStatus.snoozed.rawValue
        try await scheduler.scheduleSnooze(task, until: snoozeTarget)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].identifier == "task-\(task.id.uuidString)")
        #expect(pending[0].triggerDay == 6)
        #expect(pending[0].triggerHour == 9)
        #expect(pending[0].triggerMinute == 0)
    }
}
