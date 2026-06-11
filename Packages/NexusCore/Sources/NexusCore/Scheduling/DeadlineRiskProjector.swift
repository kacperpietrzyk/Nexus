import Foundation
import SwiftData

/// Assembles the inputs a `DeadlineRiskAnalyzer` needs from the store and runs it
/// (spec §19.1). Consolidates the open-task + completion-history fetch next to the
/// analyzer so in-app surfaces (the Today banner) and the `schedule.deadline_risks`
/// agent tool share one query path instead of re-deriving it. Pure data plumbing:
/// calendar events come from the caller (the UI fetches them via the provider), so
/// this stays EventKit-free and `@MainActor`-bound only for the SwiftData reads.
public enum DeadlineRiskProjector {
    /// Project deadline risk over the open worklist. `events` are calendar
    /// obstacles already fetched for `[now, now + horizon]`; absent calendar
    /// access degrades to `[]` (valid per spec §13 — risk still reflects raw
    /// working-window capacity).
    @MainActor
    public static func project(
        context: ModelContext,
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        estimator: any DurationEstimator = HeuristicDurationEstimator(),
        horizon: TimeInterval,
        now: Date,
        calendar: Calendar = .current
    ) -> [DeadlineRisk] {
        let openTasks = (try? fetchOpenTasks(context: context)) ?? []
        let history = (try? fetchHistory(context: context)) ?? []
        return DeadlineRiskAnalyzer().analyze(
            tasks: openTasks,
            events: events,
            prefs: prefs,
            estimator: estimator,
            history: history,
            horizon: horizon,
            now: now,
            calendar: calendar
        )
    }

    /// All open, non-deleted tasks — the universe the analyzer projects over (it
    /// filters to those with a deadline inside the horizon itself, spec §19.1).
    @MainActor
    static func fetchOpenTasks(context: ModelContext) throws -> [TaskItem] {
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.deletedAt == nil && task.statusRaw == openStatus
                    && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor)
    }

    /// Completion-history corpus for the estimator (spec §5): completed tasks with
    /// an explicit, known duration. The `HeuristicDurationEstimator` also defends
    /// this, but pre-filtering keeps the corpus small.
    @MainActor
    static func fetchHistory(context: ModelContext) throws -> [TaskItem] {
        let doneStatus = TaskStatus.done.rawValue
        let explicit = DurationSource.explicit.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.deletedAt == nil
                    && task.statusRaw == doneStatus
                    && task.durationSourceRaw == explicit
                    && task.estimatedDurationSeconds != nil
            }
        )
        // I-D1 defensive: a fifth `#Predicate` conjunct blows the type-checker
        // budget here; templates can never be done post-guard, so this only
        // shields against pre-guard synced rows.
        return try context.fetch(descriptor).filter { !$0.isTemplate }
    }
}
