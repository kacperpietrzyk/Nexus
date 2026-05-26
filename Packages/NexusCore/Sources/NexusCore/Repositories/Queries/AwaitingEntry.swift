import Foundation

/// One row in the `AWAITING YOU` bucket: a task that blocks at least one
/// other open task, paired with how many open tasks it currently blocks.
/// Used by `TodayQuery.awaiting(now:)`.
public struct AwaitingEntry {
    public let task: TaskItem
    public let blockedCount: Int

    public init(task: TaskItem, blockedCount: Int) {
        self.task = task
        self.blockedCount = blockedCount
    }
}
