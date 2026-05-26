import Foundation
import SwiftData

public enum ProjectSectionAssignmentError: Error, Equatable {
    case sectionRequiresProject(sectionID: UUID)
    case sectionNotFound(sectionID: UUID)
    case sectionProjectMismatch(sectionID: UUID, expectedProjectID: UUID, actualProjectID: UUID)
    case cannotReassignSectionToItself(sectionID: UUID)
}

public enum TaskItemRepositoryError: Error, Equatable {
    case parentHasOpenSubtasks(parentID: UUID, openCount: Int)
    case projectNotFound(projectID: UUID)
}

struct TaskCompletionSideEffects {
    var cancelledTaskIDs = Set<UUID>()
    var scheduledTasks: [TaskItem] = []

    var isEmpty: Bool {
        cancelledTaskIDs.isEmpty && scheduledTasks.isEmpty
    }
}

@MainActor
enum ProjectSectionAssignmentValidator {
    static func validate(sectionID: UUID?, belongsTo projectID: UUID?, in context: ModelContext) throws {
        guard let sectionID else { return }
        guard let projectID else {
            throw ProjectSectionAssignmentError.sectionRequiresProject(sectionID: sectionID)
        }

        let descriptor = FetchDescriptor<Section>(
            predicate: #Predicate { section in
                section.id == sectionID && section.deletedAt == nil
            }
        )
        guard let section = try context.fetch(descriptor).first else {
            throw ProjectSectionAssignmentError.sectionNotFound(sectionID: sectionID)
        }
        guard section.projectID == projectID else {
            throw ProjectSectionAssignmentError.sectionProjectMismatch(
                sectionID: sectionID,
                expectedProjectID: projectID,
                actualProjectID: section.projectID
            )
        }
    }
}

/// CRUD + lifecycle operations on `TaskItem`. Bound to a single `ModelContext`;
/// never share across actors.
@MainActor
public final class TaskItemRepository {
    public let context: ModelContext
    public let scheduler: RRuleScheduler
    public let now: () -> Date
    public let notifications: any NotificationScheduling
    public let snapshotPusher: WatchSnapshotPusher

    public init(
        context: ModelContext,
        scheduler: RRuleScheduler,
        now: @escaping () -> Date,
        notifications: any NotificationScheduling = NoopNotificationScheduler(),
        snapshotPusher: @escaping WatchSnapshotPusher = noopWatchSnapshotPusher
    ) {
        self.context = context
        self.scheduler = scheduler
        self.now = now
        self.notifications = notifications
        self.snapshotPusher = snapshotPusher
    }

    public func insert(_ task: TaskItem) throws {
        task.tags = Self.normalize(tags: task.tags)
        context.insert(task)
        try context.save()
        let notifier = notifications
        Task { @MainActor in try? await notifier.schedule(task) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func update(_ task: TaskItem, mutations: (TaskItem) -> Void) throws {
        let oldRule = task.recurrenceRule
        mutations(task)
        let newRule = task.recurrenceRule
        task.tags = Self.normalize(tags: task.tags)
        task.updatedAt = now()

        var removedSpawnID: UUID?
        var insertedSpawn: TaskItem?
        if oldRule != newRule {
            let result = try regenerateNextSpawn(after: task)
            removedSpawnID = result.removed
            insertedSpawn = result.inserted
        }

        try context.save()
        let notifier = notifications
        let parent = task
        Task { @MainActor in
            if let removedSpawnID { await notifier.cancel(taskID: removedSpawnID) }
            try? await notifier.reschedule(parent)
            if let insertedSpawn { try? await notifier.schedule(insertedSpawn) }
        }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func assign(_ task: TaskItem, toProject projectID: UUID?, section sectionID: UUID? = nil) throws {
        if let projectID {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate { project in
                    project.id == projectID && project.deletedAt == nil
                }
            )
            guard try context.fetch(descriptor).first != nil else {
                throw TaskItemRepositoryError.projectNotFound(projectID: projectID)
            }
        }
        try ProjectSectionAssignmentValidator.validate(sectionID: sectionID, belongsTo: projectID, in: context)
        task.projectID = projectID
        task.sectionID = sectionID
        task.updatedAt = now()
        try context.save()
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func tasks(in projectID: UUID, section sectionID: UUID? = nil) throws -> [TaskItem] {
        let descriptor: FetchDescriptor<TaskItem>
        if let sectionID {
            descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.projectID == projectID && task.sectionID == sectionID && task.deletedAt == nil
                }
            )
        } else {
            descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.projectID == projectID && task.deletedAt == nil
                }
            )
        }
        return try context.fetch(descriptor).sorted(by: Self.assignmentOrder)
    }

    public func snooze(_ task: TaskItem, until: Date) throws {
        task.snoozedUntil = until
        task.statusRaw = TaskStatus.snoozed.rawValue
        task.updatedAt = now()
        try context.save()
        let notifier = notifications
        Task { @MainActor in try? await notifier.scheduleSnooze(task, until: until) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func unsnooze(_ task: TaskItem) throws {
        guard let snoozedUntil = task.snoozedUntil, snoozedUntil <= now() else {
            return
        }
        task.snoozedUntil = nil
        task.statusRaw = TaskStatus.open.rawValue
        task.updatedAt = now()
        try context.save()
        let notifier = notifications
        Task { @MainActor in try? await notifier.reschedule(task) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    /// Reverts a previously-completed task back to `.open` and clears
    /// `lastCompletedAt`. For recurring tasks, also removes the spawned
    /// next-occurrence that `markDone` inserted as a side effect, so that
    /// cycling Done/Reopen does not accumulate phantom rows.
    public func reopen(_ task: TaskItem) throws {
        if task.statusRaw == TaskStatus.open.rawValue && task.lastCompletedAt == nil {
            return
        }

        var removedSpawnID: UUID?
        if task.recurrenceRule != nil {
            removedSpawnID = try removeSpawnedNextOccurrence(after: task)
        }
        task.statusRaw = TaskStatus.open.rawValue
        task.lastCompletedAt = nil
        task.updatedAt = now()
        try context.save()
        let notifier = notifications
        Task { @MainActor in
            if let removedSpawnID { await notifier.cancel(taskID: removedSpawnID) }
            try? await notifier.reschedule(task)
        }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func markDone(_ task: TaskItem) throws {
        let stamp = now()
        var sideEffects = TaskCompletionSideEffects()
        try completeTask(task, stamp: stamp, sideEffects: &sideEffects)
        // `completeTask` returns early without registering side effects when the
        // task is already done (`statusRaw == .done && lastCompletedAt != nil`).
        // In that case there is nothing to persist or dispatch.
        guard sideEffects.isEmpty == false else { return }
        try context.save()
        dispatchCompletionSideEffects(sideEffects)
    }

    func completeTask(
        _ task: TaskItem,
        stamp: Date,
        sideEffects: inout TaskCompletionSideEffects
    ) throws {
        if task.statusRaw == TaskStatus.done.rawValue && task.lastCompletedAt != nil {
            return
        }

        task.statusRaw = TaskStatus.done.rawValue
        task.lastCompletedAt = stamp
        task.updatedAt = stamp
        sideEffects.cancelledTaskIDs.insert(task.id)

        guard let ruleText = task.recurrenceRule else {
            return
        }

        let rule = try RRuleParser.parse(ruleText)
        let parentID = task.recurrenceParentId ?? task.id
        let occurrencesSoFar = try countSiblings(parentID: parentID) + 1
        let recurrenceAnchor = task.dueAt ?? stamp
        guard
            let nextDate = scheduler.next(
                after: recurrenceAnchor,
                rule: rule,
                occurrencesSoFar: occurrencesSoFar
            )
        else {
            return
        }

        if try existsOccurrence(parentID: parentID, dueAt: nextDate) {
            return
        }

        let nextInstance = makeNextOccurrence(
            from: task,
            dueAt: nextDate,
            recurrenceAnchor: recurrenceAnchor,
            recurrenceRule: ruleText,
            parentID: parentID
        )
        context.insert(nextInstance)
        sideEffects.scheduledTasks.append(nextInstance)
    }

    func dispatchCompletionSideEffects(_ sideEffects: TaskCompletionSideEffects) {
        let notifier = notifications
        let cancelledTaskIDs = sideEffects.cancelledTaskIDs
        let scheduledTasks = sideEffects.scheduledTasks
        Task { @MainActor in
            for taskID in cancelledTaskIDs {
                await notifier.cancel(taskID: taskID)
            }
            for task in scheduledTasks {
                try? await notifier.schedule(task)
            }
        }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    static func normalize(tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for tag in tags {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            normalized.append(cleaned)
        }
        return normalized
    }

    static func assignmentOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.orderIndex, rhs.orderIndex) {
        case (let left?, let right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func countSiblings(parentID: UUID) throws -> Int {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.recurrenceParentId == parentID
            }
        )
        return try context.fetch(descriptor).count
    }

    /// Removes the immediate next-occurrence sibling spawned by a prior
    /// `markDone`. Identifies the spawn as the open, never-completed sibling
    /// with the smallest `dueAt` strictly greater than the reopened task's
    /// own `dueAt`. Filtering is split between `#Predicate` (for indexable
    /// fields) and in-memory comparison (because `#Predicate` cannot express
    /// optional `Date >` cleanly).
    private func removeSpawnedNextOccurrence(after task: TaskItem) throws -> UUID? {
        let parentID = task.recurrenceParentId ?? task.id
        let openRaw = TaskStatus.open.rawValue
        let predicate = #Predicate<TaskItem> { sibling in
            sibling.recurrenceParentId == parentID
                && sibling.deletedAt == nil
                && sibling.lastCompletedAt == nil
                && sibling.statusRaw == openRaw
        }
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
        let openSiblings = try context.fetch(descriptor)
        let baseDue = task.dueAt
        let taskID = task.id
        let candidates = openSiblings.compactMap { sibling -> (TaskItem, Date)? in
            guard sibling.id != taskID, let siblingDue = sibling.dueAt else { return nil }
            if let base = baseDue, siblingDue <= base { return nil }
            return (sibling, siblingDue)
        }
        if let next = candidates.min(by: { $0.1 < $1.1 })?.0 {
            let removedID = next.id
            context.delete(next)
            return removedID
        }
        return nil
    }

    private func existsOccurrence(parentID: UUID, dueAt: Date) throws -> Bool {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.recurrenceParentId == parentID
                    && task.deletedAt == nil
                    && task.dueAt == dueAt
            }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    /// Regenerates the next-occurrence spawn after a `recurrenceRule` change on
    /// a done parent. Mirrors `reopen` removal and `markDone` insertion in one
    /// save transaction.
    private func regenerateNextSpawn(after task: TaskItem) throws -> (removed: UUID?, inserted: TaskItem?) {
        guard task.statusRaw == TaskStatus.done.rawValue else {
            return (nil, nil)
        }

        let removedID = try removeSpawnedNextOccurrence(after: task)

        guard let newRule = task.recurrenceRule else {
            return (removedID, nil)
        }

        let rule = try RRuleParser.parse(newRule)
        let parentID = task.recurrenceParentId ?? task.id
        let occurrencesSoFar = try countSiblings(parentID: parentID) + 1
        let recurrenceAnchor = task.dueAt ?? now()
        guard
            let nextDate = scheduler.next(
                after: recurrenceAnchor,
                rule: rule,
                occurrencesSoFar: occurrencesSoFar
            )
        else {
            return (removedID, nil)
        }

        if try existsOccurrence(parentID: parentID, dueAt: nextDate) {
            return (removedID, nil)
        }

        let nextInstance = makeNextOccurrence(
            from: task,
            dueAt: nextDate,
            recurrenceAnchor: recurrenceAnchor,
            recurrenceRule: newRule,
            parentID: parentID
        )
        context.insert(nextInstance)
        return (removedID, nextInstance)
    }

    public func allExternalSourceIDs(withPrefix prefix: String) throws -> [String] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.externalSourceID != nil
            }
        )
        return try context.fetch(descriptor).compactMap(\.externalSourceID).filter {
            $0.hasPrefix(prefix)
        }
    }

    private func makeNextOccurrence(
        from task: TaskItem,
        dueAt nextDate: Date,
        recurrenceAnchor: Date,
        recurrenceRule: String,
        parentID: UUID
    ) -> TaskItem {
        let parentDuration: TimeInterval? =
            if let startAt = task.startAt, let endAt = task.endAt {
                endAt.timeIntervalSince(startAt)
            } else {
                nil
            }
        let intervalDelta = nextDate.timeIntervalSince(recurrenceAnchor)
        let nextStartAt = task.startAt?.addingTimeInterval(intervalDelta)
        let nextEndAt: Date? =
            if let nextStartAt, let parentDuration {
                nextStartAt.addingTimeInterval(parentDuration)
            } else {
                nil
            }

        return TaskItem(
            title: task.title,
            body: task.body,
            dueAt: nextDate,
            startAt: nextStartAt,
            endAt: nextEndAt,
            priority: task.priority,
            status: .open,
            tags: task.tags,
            recurrenceRule: recurrenceRule,
            recurrenceParentId: parentID,
            orderIndex: task.orderIndex,
            pinnedAsFocus: task.pinnedAsFocus
        )
    }
}
