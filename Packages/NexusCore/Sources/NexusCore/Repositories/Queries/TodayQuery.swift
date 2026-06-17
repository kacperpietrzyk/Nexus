import Foundation
import SwiftData

/// Buckets feeding the Today view: overdue, today, and no-date.
public struct TodayQuery: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func overdue(now: Date, excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let startOfDay = calendar.startOfDay(for: now)
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.dueAt != nil
                && task.isTemplate == false
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in
                guard let due = task.dueAt else { return false }
                if let projectID = task.projectID, excludingProjectIDs.contains(projectID) {
                    return false
                }
                return due < startOfDay
            },
            sort: [SortDescriptor(\TaskItem.dueAt, order: .forward)]
        )
    }

    public func today(now: Date, excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let startOfDay = calendar.startOfDay(for: now)
        let startOfTomorrow =
            calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.dueAt != nil
                && task.isTemplate == false
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in
                guard let due = task.dueAt else { return false }
                if let projectID = task.projectID, excludingProjectIDs.contains(projectID) {
                    return false
                }
                return due >= startOfDay && due < startOfTomorrow
            },
            sort: [SortDescriptor(\TaskItem.dueAt, order: .forward)],
            // Respect a persisted manual reorder; falls back to the dueAt sort
            // above until the user actually drags a row.
            comparator: OrderIndex.manualThenDueOrder
        )
    }

    public func noDate(excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.dueAt == nil
                && task.isTemplate == false
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in
                if let projectID = task.projectID, excludingProjectIDs.contains(projectID) {
                    return false
                }
                return true
            },
            sort: [
                SortDescriptor(\TaskItem.priorityRaw, order: .reverse),
                SortDescriptor(\TaskItem.createdAt, order: .reverse),
            ]
        )
    }

    /// Inbox-ordered variant of `noDate` for WINDOWED loading: identical
    /// predicate + post-filter (so the SET of surfaced tasks is byte-for-byte the
    /// same as `noDate()` — subtasks included, archived-project tasks excluded
    /// in-memory), but sorted to match the Inbox's GLOBAL comparator
    /// (`createdAt` desc, then a stable `id` tiebreak) instead of `noDate()`'s
    /// `priorityRaw`-first Today ordering.
    ///
    /// This sort is what makes paging composable with the Inbox merge: a window
    /// streamed in `createdAt`-desc order always extends the loaded prefix at the
    /// tail (a later page never carries a *newer* item that belongs above an
    /// already-shown row). The `id` tiebreak gives offset/limit paging a unique
    /// total order so consecutive windows are gap-free and overlap-free even when
    /// many tasks share a `createdAt` (true here — the migration back-dated
    /// `created_at`). Kept SEPARATE from `noDate()` so its many non-windowed
    /// callers stay byte-for-byte unchanged.
    public func noDateInboxWindow(excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.dueAt == nil
                && task.isTemplate == false
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in
                if let projectID = task.projectID, excludingProjectIDs.contains(projectID) {
                    return false
                }
                return true
            },
            sort: [
                SortDescriptor(\TaskItem.createdAt, order: .reverse),
                SortDescriptor(\TaskItem.id, order: .forward),
            ]
        )
    }

    /// Root-only variant of `noDate` for WINDOWED loading: identical predicate
    /// plus `parentTaskID == nil` hoisted DB-side, so a `TaskBucket.page` fetch
    /// pages only root tasks and doesn't burn a raw page on no-date subtasks that
    /// the Tasks list drops afterward (which would badly undershoot the page size
    /// on a store with many subtasks). Order-identical to `rootTasks(noDate())`:
    /// the only DB-visible difference is excluding the same subtasks the caller's
    /// root reduction already removes. Kept SEPARATE from `noDate()` so the many
    /// non-windowed callers that consume the raw bucket (Inbox source, HeroBrief
    /// counts, digest, embedded Today) are byte-for-byte unchanged.
    ///
    /// `deletedAt`/`isTemplate` move to the post-filter here only because a fourth
    /// `== nil` predicate conjunct (`deletedAt`, `dueAt`, `parentTaskID`) blows the
    /// `#Predicate` type-checker budget; the resulting set is identical.
    public func noDateRoots(excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.statusRaw == openStatus
                && task.dueAt == nil
                && task.parentTaskID == nil
        }
        return TaskBucket(
            predicate: predicate,
            postFilter: { task in
                if task.deletedAt != nil { return false }
                if task.isTemplate { return false }
                if let projectID = task.projectID, excludingProjectIDs.contains(projectID) {
                    return false
                }
                return true
            },
            sort: [
                SortDescriptor(\TaskItem.priorityRaw, order: .reverse),
                SortDescriptor(\TaskItem.createdAt, order: .reverse),
            ]
        )
    }

    @MainActor
    public func awaiting(
        now: Date,
        modelContext: ModelContext,
        linkRepository: LinkRepository
    ) throws -> [AwaitingEntry] {
        let openStatus = TaskStatus.open.rawValue
        let openPredicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.statusRaw == openStatus && task.isTemplate == false
        }
        let openTasks = try modelContext.fetch(FetchDescriptor<TaskItem>(predicate: openPredicate))
        // Synced entities cannot use @Attribute(.unique) (CloudKit forbids it), so two open
        // tasks can share an id after a sync conflict / re-import. uniqueKeysWithValues would
        // trap on the duplicate; dedup keep-first instead (behavior-identical when ids unique).
        let openTaskByID = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })

        // One batched fetch of every open task's outgoing edges instead of an
        // N+1 storm (one fetch per open task). The per-task `.blocks` + open-target
        // discrimination below is byte-for-byte the same work the old loop did.
        let outgoingByTask = try linkRepository.outgoing(fromKind: .task, fromIDs: openTasks.map(\.id))

        var entries: [AwaitingEntry] = []
        for task in openTasks {
            let outgoing = (outgoingByTask[task.id] ?? []).filter { $0.linkKind == .blocks }
            let openBlockedTaskIDs = outgoing.reduce(into: Set<UUID>()) { ids, link in
                if link.toKind == .task && openTaskByID[link.toID] != nil {
                    ids.insert(link.toID)
                }
            }
            let openBlockedCount = openBlockedTaskIDs.count
            if openBlockedCount > 0 {
                entries.append(AwaitingEntry(task: task, blockedCount: openBlockedCount))
            }
        }

        entries.sort { lhs, rhs in
            if lhs.blockedCount != rhs.blockedCount {
                return lhs.blockedCount > rhs.blockedCount
            }
            switch (lhs.task.dueAt, rhs.task.dueAt) {
            case (let lhsDue?, let rhsDue?):
                return lhsDue < rhsDue
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.task.title < rhs.task.title
            }
        }
        return entries
    }
}
