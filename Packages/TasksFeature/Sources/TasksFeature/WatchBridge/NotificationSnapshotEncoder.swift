import Foundation
import NexusCore
import SwiftData

/// Builds a `NotificationSnapshot` from the live `ModelContext`. Filters to
/// open or snoozed, non-deleted tasks with a due/snooze trigger that lands
/// within `[now, now + horizon]`, sorted ascending by effective trigger time.
@MainActor
public struct NotificationSnapshotEncoder {
    public let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func encodeNow(horizon: TimeInterval = 24 * 3_600) -> NotificationSnapshot {
        encode(now: Date(), horizon: horizon)
    }

    public func encode(now: Date, horizon: TimeInterval) -> NotificationSnapshot {
        let openRaw = TaskStatus.open.rawValue
        let snoozedRaw = TaskStatus.snoozed.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil
                    && (task.statusRaw == openRaw || task.statusRaw == snoozedRaw)
                    && task.isTemplate == false
            }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        let upper = now.addingTimeInterval(horizon)
        let entries =
            tasks
            .compactMap { task -> NotificationSnapshotEntry? in
                guard let trigger = task.snoozedUntil ?? task.dueAt else { return nil }
                guard trigger >= now, trigger <= upper else { return nil }
                return NotificationSnapshotEntry(
                    id: task.id,
                    title: task.title,
                    dueAt: task.dueAt,
                    projectName: nil,  // Phase 1 has no Project model yet.
                    snoozedUntil: task.snoozedUntil
                )
            }
            .sorted { $0.effectiveTriggerAt < $1.effectiveTriggerAt }

        return NotificationSnapshot(entries: entries, generatedAt: now, horizon: horizon)
    }
}
