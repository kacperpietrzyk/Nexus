import Foundation
import NexusCore
import SwiftData
import Testing
@preconcurrency import UserNotifications

@testable import NexusWatch

@MainActor
private final class RecordingBridge: WatchActionSending {
    var sentSnooze: [(taskID: UUID, until: Date)] = []
    var sentMarkDone: [UUID] = []
    var sentReopen: [UUID] = []

    func sendSnoozeAction(taskID: UUID, until: Date) async throws {
        sentSnooze.append((taskID, until))
    }

    func sendMarkDone(taskID: UUID) async throws {
        sentMarkDone.append(taskID)
    }

    func sendReopen(taskID: UUID) async throws {
        sentReopen.append(taskID)
    }
}

private final class NoopDelivery: NotificationDelivering, @unchecked Sendable {
    func add(_: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers _: [String]) async {}
    func removeAllPendingNotificationRequests() async {}
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func setNotificationCategories(_: Set<UNNotificationCategory>) async {}
    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool { true }
    func notificationSettings() async -> UNNotificationSettings {
        fatalError("not used in these tests")
    }
}

private struct Harness {
    let handler: WatchNotificationActionHandler
    let task: TaskItem
    let context: ModelContext
    let bridge: RecordingBridge
    let scheduler: WatchNotificationScheduler
}

@Suite("WatchNotificationActionHandler")
@MainActor
struct WatchNotificationActionHandlerTests {

    private func makeHarness() throws -> Harness {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let task = TaskItem(title: "x", dueAt: Date().addingTimeInterval(60))
        context.insert(task)
        try context.save()

        let bridge = RecordingBridge()
        let scheduler = WatchNotificationScheduler(delivery: NoopDelivery())
        let handler = WatchNotificationActionHandler(
            context: context,
            bridge: bridge,
            scheduler: scheduler,
            quietHoursStore: nil,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return Harness(
            handler: handler,
            task: task,
            context: context,
            bridge: bridge,
            scheduler: scheduler
        )
    }

    @Test func snooze_15m_writes_local_state_and_pushes_bridge() async throws {
        let harness = try makeHarness()
        await harness.handler.handle(
            actionID: NotificationActionID.snooze15M.rawValue,
            taskID: harness.task.id
        )
        #expect(harness.task.statusRaw == TaskStatus.snoozed.rawValue)
        let expected = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(15 * 60)
        #expect(abs((harness.task.snoozedUntil ?? .distantPast).timeIntervalSince(expected)) < 1)
        #expect(harness.bridge.sentSnooze.count == 1)
        #expect(harness.bridge.sentSnooze.first?.taskID == harness.task.id)
    }

    @Test func done_action_marks_task_done() async throws {
        let harness = try makeHarness()
        await harness.handler.handle(
            actionID: NotificationActionID.done.rawValue,
            taskID: harness.task.id
        )
        #expect(harness.task.statusRaw == TaskStatus.done.rawValue)
        #expect(harness.task.lastCompletedAt != nil)
        // Allow the detached Task that calls the bridge to run.
        try await _Concurrency.Task.sleep(for: .milliseconds(50))
        #expect(harness.bridge.sentMarkDone.contains(harness.task.id))
    }

    @Test func snooze_tomorrow_uses_next_morning_nine() async throws {
        let harness = try makeHarness()
        await harness.handler.handle(
            actionID: NotificationActionID.snoozeTomorrow.rawValue,
            taskID: harness.task.id
        )
        #expect(harness.task.statusRaw == TaskStatus.snoozed.rawValue)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: day)!
        let expected = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let actual = harness.task.snoozedUntil!
        #expect(abs(actual.timeIntervalSince(expected)) < 1)

        try await _Concurrency.Task.sleep(for: .milliseconds(50))
        #expect(harness.bridge.sentSnooze.count == 1)
        let bridged = harness.bridge.sentSnooze.first!
        #expect(abs(bridged.until.timeIntervalSince(expected)) < 1)
    }

    @Test func unknown_action_is_noop() async throws {
        let harness = try makeHarness()
        await harness.handler.handle(actionID: "WAT", taskID: harness.task.id)
        #expect(harness.task.statusRaw == TaskStatus.open.rawValue)
        #expect(harness.bridge.sentSnooze.isEmpty)
        #expect(harness.bridge.sentMarkDone.isEmpty)
    }
}
