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
    /// Non-nil when the request uses a `UNTimeIntervalNotificationTrigger`
    /// (the overdue "fire soon" fallback) instead of a calendar trigger.
    let triggerInterval: TimeInterval?
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
                let interval = request.trigger as? UNTimeIntervalNotificationTrigger
                return RequestSnapshot(
                    identifier: request.identifier,
                    title: request.content.title,
                    categoryIdentifier: request.content.categoryIdentifier,
                    triggerDay: trigger?.dateComponents.day,
                    triggerHour: trigger?.dateComponents.hour,
                    triggerMinute: trigger?.dateComponents.minute,
                    triggerInterval: interval?.timeInterval
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

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("schedule adds a request keyed task-<uuid>")
    func scheduleAddsRequest() async throws {
        let center = RecordingNotificationCenter()
        // Fixed "now" well before the due date so the scheduler treats it as
        // future (calendar-trigger path) deterministically, regardless of the
        // wall clock the suite runs on.
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(
            title: "Reply Magda",
            dueAt: date("2026-05-06T13:00:00Z")
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
        let now = date("2026-05-05T20:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { quiet },
            calendar: cal(),
            now: { now }
        )
        let inQuietHours = date("2026-05-05T23:00:00Z")
        let task = TaskItem(title: "Late reminder", dueAt: inQuietHours)
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].triggerHour == 7)
        #expect(pending[0].triggerMinute == 0)
    }

    @Test("cancel removes the legacy id and all per-reminder ids up to r31")
    func cancelRemoves() async {
        let center = RecordingNotificationCenter()
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal()
        )
        let id = UUID()
        await scheduler.cancel(taskID: id)
        let base = "task-\(id.uuidString)"
        // Legacy single id + r0…r31 = 33 identifiers.
        #expect(center.removedIdentifiers.count == 33)
        #expect(center.removedIdentifiers.first == base)
        #expect(center.removedIdentifiers.contains("\(base)-r0"))
        #expect(center.removedIdentifiers.contains("\(base)-r31"))
    }

    @Test("cancel removes scheduled reminder ids beyond r31")
    func cancelRemovesScheduledReminderIDsBeyondR31() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(title: "many reminders")
        task.reminders = (0..<34).map { index in
            .absolute(now.addingTimeInterval(TimeInterval(index + 1) * 3_600))
        }

        try await scheduler.schedule(task)
        await scheduler.cancel(taskID: task.id)

        let base = "task-\(task.id.uuidString)"
        #expect(center.removedIdentifiers.contains("\(base)-r31"))
        #expect(center.removedIdentifiers.contains("\(base)-r32"))
        #expect(center.removedIdentifiers.contains("\(base)-r33"))
    }

    @Test("scheduleSnooze adds a request keyed task-<uuid> using the snooze target")
    func scheduleSnoozeUsesUntilDate() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let snoozeTarget = date("2026-05-06T09:00:00Z")
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

    @Test("schedule fires soon for an overdue task instead of a dead calendar trigger")
    func overduePastDueFiresSoon() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-10T12:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        // Due an hour in the past relative to the injected now.
        let task = TaskItem(title: "Overdue", dueAt: date("2026-05-10T11:00:00Z"))
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        // A calendar trigger built from a past date would never fire; the
        // overdue path uses a short time-interval trigger instead.
        #expect(pending[0].triggerInterval != nil)
        #expect((pending[0].triggerInterval ?? 0) > 0)
        #expect((pending[0].triggerInterval ?? 0) <= 60)
        #expect(pending[0].triggerHour == nil, "overdue request must not use a calendar trigger")
    }

    @Test("overdue task defers its soon-trigger out of an active quiet window")
    func overdueDuringQuietHoursDefersToWindowEnd() async throws {
        let center = RecordingNotificationCenter()
        let quiet = QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0)
        // now is inside the quiet window; the task is already overdue.
        let now = date("2026-05-10T23:30:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { quiet },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(title: "Overdue in quiet hours", dueAt: date("2026-05-10T20:00:00Z"))
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending[0].triggerInterval != nil)
        // Window ends at 07:00 next day → ~7.5h out, well beyond the 5s minimum.
        #expect((pending[0].triggerInterval ?? 0) > 60)
    }

    @Test("schedule creates one request per reminder rule keyed task-<uuid>-r<index>")
    func schedulesOneRequestPerReminder() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(title: "multi", dueAt: date("2026-05-06T13:00:00Z"))
        task.reminders = [
            .relative(offset: -1800, anchor: .due),
            .absolute(date("2026-05-06T15:00:00Z")),
        ]
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.identifier.hasPrefix("task-\(task.id.uuidString)-r") })
    }

    @Test("configured reminders with past fire dates are skipped")
    func configuredPastRemindersAreSkipped() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(title: "past configured reminders", dueAt: date("2026-05-01T07:45:00Z"))
        task.reminders = [
            .relative(offset: -1800, anchor: .due),
            .absolute(date("2026-05-01T07:30:00Z")),
        ]

        try await scheduler.schedule(task)

        #expect(center.snapshots().isEmpty)
    }

    @Test("empty reminders falls back to the legacy task-<uuid> request")
    func emptyRemindersFallsBackToLegacyDueRequest() async throws {
        let center = RecordingNotificationCenter()
        let now = date("2026-05-01T08:00:00Z")
        let scheduler = NotificationScheduler(
            delivery: center,
            quietHours: { nil },
            calendar: cal(),
            now: { now }
        )
        let task = TaskItem(title: "legacy", dueAt: date("2026-05-06T13:00:00Z"))
        try await scheduler.schedule(task)
        let pending = center.snapshots()
        #expect(pending.count == 1)
        #expect(pending.first?.identifier == "task-\(task.id.uuidString)")
    }
}
