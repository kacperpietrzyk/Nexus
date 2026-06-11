import Foundation

/// Pure candidate selection for the "Plan my day" ritual (spec §6 / §10).
///
/// The scheduler's candidate pool is the open worklist: **overdue**
/// (`dueAt < startOfDay`) + **due-today** + **pinned** (`pinnedAsFocus`). Only
/// `.open` tasks qualify (done/snoozed/templates are excluded). "Later"-dated tasks are
/// pulled in only by pinning. Deterministic and timezone-explicit — `now` and
/// `calendar` are injected so the same input yields the same candidates, which
/// keeps the downstream `DayScheduler` deterministic (spec §6 / §14).
///
/// Lives in NexusCore (not a feature module) so both the Calendar surface and the
/// Tasks Today rail can build "Plan my day" without importing each other.
public enum DayPlanCandidates {
    /// Select scheduler candidates from a set of tasks.
    ///
    /// - Parameters:
    ///   - tasks: the open task universe (caller already excludes soft-deleted).
    ///   - now: the planning instant.
    ///   - calendar: timezone-explicit calendar for the day boundary.
    public static func select(from tasks: [TaskItem], now: Date, calendar: Calendar) -> [TaskItem] {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return tasks.filter { task in
            guard task.deletedAt == nil, task.status == .open, !task.isTemplate else { return false }
            if task.pinnedAsFocus { return true }
            guard let due = task.dueAt else { return false }
            // Overdue (before today) or due today.
            return due < startOfTomorrow
        }
    }
}
