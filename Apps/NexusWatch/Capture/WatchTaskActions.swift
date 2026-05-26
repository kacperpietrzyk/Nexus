import Foundation
import NexusCore
import SwiftData
import SwiftUI

/// Abstraction over WatchPhoneBridge so WatchTaskActions and the
/// notification action handler can be unit-tested without spinning up
/// WCSession.
@MainActor
protocol WatchActionSending {
    func sendMarkDone(taskID: UUID) async throws
    func sendReopen(taskID: UUID) async throws
    func sendSnoozeAction(taskID: UUID, until: Date) async throws
}

extension WatchPhoneBridge: WatchActionSending {
    func sendMarkDone(taskID: UUID) async throws {
        try await sendAction(type: "mark-done", taskID: taskID)
    }

    func sendReopen(taskID: UUID) async throws {
        try await sendAction(type: "reopen", taskID: taskID)
    }
}

/// Watch-side optimistic flip + bridge call. Local SwiftData mutation gives
/// instant UI feedback; iPhone runs the canonical TaskItemRepository.markDone
/// or reopen when the payload lands. Watch deliberately does not spawn the
/// recurring next-occurrence; iPhone owns that.
@MainActor
final class WatchTaskActions {
    private let context: ModelContext
    private let bridge: WatchActionSending
    private let now: () -> Date

    init(
        context: ModelContext,
        bridge: WatchActionSending,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.bridge = bridge
        self.now = now
    }

    func markDone(_ task: TaskItem) async throws {
        guard !(task.statusRaw == TaskStatus.done.rawValue && task.lastCompletedAt != nil) else {
            return
        }
        let stamp = now()
        task.statusRaw = TaskStatus.done.rawValue
        task.lastCompletedAt = stamp
        task.updatedAt = stamp
        try context.save()
        try await bridge.sendMarkDone(taskID: task.id)
    }

    func reopen(_ task: TaskItem) async throws {
        guard !(task.statusRaw == TaskStatus.open.rawValue && task.lastCompletedAt == nil) else {
            return
        }
        task.statusRaw = TaskStatus.open.rawValue
        task.lastCompletedAt = nil
        task.updatedAt = now()
        try context.save()
        try await bridge.sendReopen(taskID: task.id)
    }
}

private struct WatchTaskActionsKey: EnvironmentKey {
    static let defaultValue: WatchTaskActions? = nil
}

extension EnvironmentValues {
    var watchTaskActions: WatchTaskActions? {
        get { self[WatchTaskActionsKey.self] }
        set { self[WatchTaskActionsKey.self] = newValue }
    }
}
