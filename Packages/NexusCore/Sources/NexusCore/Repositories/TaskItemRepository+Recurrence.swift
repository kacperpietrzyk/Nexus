import Foundation

// MARK: - Recurrence anchor resolution (T1 completion-based recurrence)

extension TaskItemRepository {
    /// Resolves the next occurrence date honoring the rule's anchor mode
    /// (T1 completion-based recurrence):
    /// - `.dueDate` (default): advance from the current due date — the
    ///   completion stamp only when the task has no due date. Pre-anchor
    ///   behavior, unchanged.
    /// - `.completion`: Todoist "every!" — advance from the completion stamp,
    ///   then re-apply the original due time-of-day so a "daily 09:00" task
    ///   completed at 14:30 spawns tomorrow 09:00, not tomorrow 14:30.
    func nextOccurrenceDate(
        rule: RRule,
        dueAt: Date?,
        completedAt stamp: Date,
        occurrencesSoFar: Int
    ) -> Date? {
        switch rule.anchor {
        case .dueDate:
            return scheduler.next(after: dueAt ?? stamp, rule: rule, occurrencesSoFar: occurrencesSoFar)
        case .completion:
            guard
                let advanced = scheduler.next(after: stamp, rule: rule, occurrencesSoFar: occurrencesSoFar)
            else { return nil }
            let adjusted = preservingTimeOfDay(of: dueAt, on: advanced)
            // The scheduler checked UNTIL against the raw candidate; re-check
            // after the time-of-day override nudged it.
            if let until = rule.until, adjusted > until { return nil }
            return adjusted
        }
    }

    /// Copies `source`'s hour/minute/second onto `target`'s calendar day.
    /// A nil `source` (task without a due date) leaves `target` untouched.
    private func preservingTimeOfDay(of source: Date?, on target: Date) -> Date {
        guard let source else { return target }
        let time = scheduler.calendar.dateComponents([.hour, .minute, .second], from: source)
        return scheduler.calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        ) ?? target
    }
}
