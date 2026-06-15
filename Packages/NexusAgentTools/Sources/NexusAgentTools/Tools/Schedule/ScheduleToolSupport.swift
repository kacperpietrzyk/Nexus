import Foundation
import NexusCore
import SwiftData

/// Shared candidate/history/event assembly + argument parsing for the
/// `schedule.*` tools (spec §6 / §19). Pure data plumbing over `NexusCore`
/// queries — no EventKit (events come from an injected read provider; absent
/// access degrades to `[]`, valid per spec §13).
enum ScheduleToolSupport {
    /// Open worklist candidates (spec §6): overdue + due-today + pinned, deduped
    /// by id. Reuses `TodayQuery` for the date buckets; pinned is a direct fetch
    /// (open, not deleted, `pinnedAsFocus`). Deterministic order is the
    /// scheduler's job — callers hand this set straight to `DayScheduler.plan`.
    @MainActor
    static func candidates(context: ModelContext, now: Date) throws -> [TaskItem] {
        let query = TodayQuery()
        let overdue = try query.overdue(now: now).apply(in: context)
        let today = try query.today(now: now).apply(in: context)
        let pinned = try pinnedCandidates(context: context)

        var seen = Set<UUID>()
        var result: [TaskItem] = []
        for task in overdue + today + pinned where seen.insert(task.id).inserted {
            result.append(task)
        }
        return result
    }

    /// Pinned open tasks (`pinnedAsFocus == true`, open, not deleted) — the
    /// scheduler pulls these in regardless of date (spec §6).
    @MainActor
    static func pinnedCandidates(context: ModelContext) throws -> [TaskItem] {
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.deletedAt == nil
                    && task.statusRaw == openStatus
                    && task.pinnedAsFocus
                    && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor)
    }

    /// History corpus for the estimator (spec §5): completed tasks with a known
    /// (explicit) duration. The `HeuristicDurationEstimator` also defends this,
    /// but pre-filtering keeps the corpus small.
    @MainActor
    static func history(context: ModelContext) throws -> [TaskItem] {
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

    /// All open, non-deleted tasks (the universe the `DeadlineRiskAnalyzer`
    /// projects over — it filters to those with a deadline itself, spec §19.1).
    @MainActor
    static func openTasks(context: ModelContext) throws -> [TaskItem] {
        let openStatus = TaskStatus.open.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { task in
                task.deletedAt == nil && task.statusRaw == openStatus
                    && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor)
    }

    /// Accepted, non-deleted blocks intersecting `[start, end)` — hard input to the
    /// scheduler (anti-thrash, spec §6). Proposed blocks are NOT consulted: a
    /// re-plan regenerates them.
    @MainActor
    static func acceptedBlocks(
        repository: ScheduledBlockRepository,
        start: Date,
        end: Date
    ) throws -> [ScheduledBlock] {
        let acceptedRaw = ScheduledBlockStatus.accepted.rawValue
        return try repository.blocks(from: start, to: end).filter { $0.statusRaw == acceptedRaw }
    }

    /// Events as obstacles over `[start, end)` from the read provider. Returns `[]`
    /// when access is not granted (spec §13: estimate/propose still work locally;
    /// only event materialization needs access).
    static func events(
        provider: any CalendarEventProviding,
        start: Date,
        end: Date
    ) async -> [CalendarEvent] {
        guard provider.authorizationStatus() == .fullAccess else { return [] }
        return (try? await provider.eventsBetween(start: start, end: end)) ?? []
    }
}
