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
            sort: [SortDescriptor(\TaskItem.dueAt, order: .forward)]
        )
    }

    public func noDate(excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let openStatus = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == openStatus
                && task.dueAt == nil
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

    @MainActor
    public func awaiting(
        now: Date,
        modelContext: ModelContext,
        linkRepository: LinkRepository
    ) throws -> [AwaitingEntry] {
        let openStatus = TaskStatus.open.rawValue
        let openPredicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.statusRaw == openStatus
        }
        let openTasks = try modelContext.fetch(FetchDescriptor<TaskItem>(predicate: openPredicate))
        // Synced entities cannot use @Attribute(.unique) (CloudKit forbids it), so two open
        // tasks can share an id after a sync conflict / re-import. uniqueKeysWithValues would
        // trap on the duplicate; dedup keep-first instead (behavior-identical when ids unique).
        let openTaskByID = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })

        var entries: [AwaitingEntry] = []
        for task in openTasks {
            let outgoing = try linkRepository.outgoingBlocks(from: (.task, task.id))
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
