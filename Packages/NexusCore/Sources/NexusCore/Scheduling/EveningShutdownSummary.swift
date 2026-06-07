import Foundation

/// Pure evening-shutdown summary (spec §10): what got done today vs what is still
/// open. Deterministic + timezone-explicit (`now`/`calendar` injected) so it is
/// unit-testable and reusable by both the Calendar surface and the Tasks Today rail
/// without a feature-module cross-import.
public struct EveningShutdownSummary: Equatable, Sendable {
    /// Open tasks due today or overdue that are still unfinished.
    public let remainingTaskIDs: [UUID]
    /// Tasks completed today (`lastCompletedAt` within the day).
    public let completedTaskIDs: [UUID]

    public init(remainingTaskIDs: [UUID], completedTaskIDs: [UUID]) {
        self.remainingTaskIDs = remainingTaskIDs
        self.completedTaskIDs = completedTaskIDs
    }

    public var remainingCount: Int { remainingTaskIDs.count }
    public var completedCount: Int { completedTaskIDs.count }
    /// True when the day's due/overdue worklist is fully cleared.
    public var isClear: Bool { remainingTaskIDs.isEmpty }

    /// Build the summary from a task universe (caller excludes soft-deleted).
    public static func make(from tasks: [TaskItem], now: Date, calendar: Calendar) -> EveningShutdownSummary {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        var remaining: [UUID] = []
        var completed: [UUID] = []
        for task in tasks where task.deletedAt == nil {
            if task.status == .done, let stamp = task.lastCompletedAt, stamp >= startOfDay, stamp < startOfTomorrow {
                completed.append(task.id)
            } else if task.status == .open, let due = task.dueAt, due < startOfTomorrow {
                remaining.append(task.id)
            }
        }
        return EveningShutdownSummary(
            remainingTaskIDs: remaining.sorted { $0.uuidString < $1.uuidString },
            completedTaskIDs: completed.sorted { $0.uuidString < $1.uuidString }
        )
    }
}
