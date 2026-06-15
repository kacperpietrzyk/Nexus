import Foundation
import SwiftData

/// Open tasks due in the next N days, excluding today.
public struct UpcomingQuery: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func next(days: Int, from: Date, excludingProjectIDs: Set<UUID> = []) -> TaskBucket {
        let startOfTomorrow =
            calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: from)
            ) ?? from
        let endExclusive =
            calendar.date(byAdding: .day, value: days, to: startOfTomorrow)
            ?? startOfTomorrow
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
                return due >= startOfTomorrow && due < endExclusive
            },
            sort: [SortDescriptor(\TaskItem.dueAt, order: .forward)]
        )
    }
}
