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
    case parentNotFound(parentID: UUID)
    case parentIsSelf(taskID: UUID)
    case parentCycle(taskID: UUID, parentID: UUID)
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
    /// Audit-log hook (Tranche 2 Plan B, spec §4.1). Insert-only; entries ride
    /// this repository's saves (I-B1). Defaults to no-op, like `notifications`.
    public let activity: any ActivityRecording
    public let snapshotPusher: WatchSnapshotPusher

    public init(
        context: ModelContext,
        scheduler: RRuleScheduler,
        now: @escaping () -> Date,
        notifications: any NotificationScheduling = NoopNotificationScheduler(),
        activity: any ActivityRecording = NoopActivityRecorder(),
        snapshotPusher: @escaping WatchSnapshotPusher = noopWatchSnapshotPusher
    ) {
        self.context = context
        self.scheduler = scheduler
        self.now = now
        self.notifications = notifications
        self.activity = activity
        self.snapshotPusher = snapshotPusher
    }

    public func insert(_ task: TaskItem) throws {
        task.tags = Self.normalize(tags: task.tags)
        context.insert(task)
        // Templates are inert (I-D1) — authoring one is not a lifecycle event.
        if !task.isTemplate {
            activity.record(.created, itemID: task.id, itemKind: .task)
        }
        try context.save()
        let notifier = notifications
        Task { @MainActor in try? await notifier.schedule(task) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func update(_ task: TaskItem, mutations: (TaskItem) -> Void) throws {
        let oldRule = task.recurrenceRule
        let snapshot = ActivityFieldSnapshot(of: task)
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

        recordFieldChanges(on: task, since: snapshot)
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

    /// Persists an explicit manual ordering by assigning sequential
    /// `orderIndex` values (1.0, 2.0, 3.0, …) to `orderedTasks` in array order,
    /// in a single save. Unlike `update`, this does not bump `updatedAt`, touch
    /// recurrence, or reschedule notifications — `orderIndex` only affects
    /// display order — so a drag-to-reorder does not spam notification
    /// rescheduling across the whole list. Mirrors `OrderRebalanceJob.renumber`.
    /// No-op (no save) when every task already holds its target index.
    public func reorder(_ orderedTasks: [TaskItem]) throws {
        var didChange = false
        for (index, task) in orderedTasks.enumerated() {
            let target = Double(index + 1)
            if task.orderIndex != target {
                task.orderIndex = target
                didChange = true
            }
        }
        guard didChange else { return }
        try context.save()
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func assign(_ task: TaskItem, toProject projectID: UUID?, section sectionID: UUID? = nil) throws {
        try validateProjectSectionAssignment(toProject: projectID, section: sectionID)
        let oldProjectID = task.projectID
        task.projectID = projectID
        task.sectionID = sectionID
        task.updatedAt = now()
        recordProjectMove(on: task, from: oldProjectID)
        try context.save()
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    public func validateProjectSectionAssignment(toProject projectID: UUID?, section sectionID: UUID? = nil) throws {
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
        activity.record(.reopened, itemID: task.id, itemKind: .task)

        var removedSpawnID: UUID?
        if task.recurrenceRule != nil {
            removedSpawnID = try removeSpawnedNextOccurrence(after: task)
        }
        // Reopen on a project task lands in `.todo` (spec §5.3; user may bump to
        // inProgress manually). This covers every non-nil terminal state — `done`
        // AND `canceled`/`duplicate` — so I1 never leaves `status=open` paired
        // with a terminal `workflowState`. GTD tasks (nil) are untouched (I7).
        if task.workflowState != nil {
            task.workflowStateRaw = WorkflowState.todo.rawValue
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
        // Single completion choke point (spec §4.1): one `completed` event per
        // real completion, regardless of entry path. The caller always saves
        // when this method passes the guard (it registers side effects).
        activity.record(.completed, itemID: task.id, itemKind: .task)

        // Project tasks (`workflowState != nil`) complete by advancing the
        // machine to `.done` (spec §5.3); GTD tasks (nil) stay nil so I7 holds.
        if task.workflowState != nil {
            task.workflowStateRaw = WorkflowState.done.rawValue
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
        // Delta base for shifting startAt/endAt/deadlineAt onto the next
        // occurrence — always the old due date, in BOTH anchor modes, so the
        // relative offsets survive however the next due date was computed.
        let recurrenceAnchor = task.dueAt ?? stamp
        guard
            let nextDate = nextOccurrenceDate(
                rule: rule,
                dueAt: task.dueAt,
                completedAt: stamp,
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
        nextInstance.noteRef = try duplicatedNoteRef(of: task.noteRef)
        context.insert(nextInstance)
        // A spawned next occurrence is a real new row (spec §4.1) — it gets
        // `created` even though it bypasses `insert(_:)`.
        activity.record(.created, itemID: nextInstance.id, itemKind: .task)
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
        // This path only runs on a done task (guard above), so the completion
        // stamp is its real `lastCompletedAt`; `now()` is a defensive fallback.
        let stamp = task.lastCompletedAt ?? now()
        let recurrenceAnchor = task.dueAt ?? stamp
        guard
            let nextDate = nextOccurrenceDate(
                rule: rule,
                dueAt: task.dueAt,
                completedAt: stamp,
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
        nextInstance.noteRef = try duplicatedNoteRef(of: task.noteRef)
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
        let nextDeadlineAt = task.deadlineAt?.addingTimeInterval(intervalDelta)

        // Content lives in a `Note` referenced by `noteRef`, not on `body`
        // (Notes content layer, spec §4.2). This pure, context-less factory copies
        // the parent's `noteRef` as a placeholder; the persisting call sites then
        // override it with a fresh per-occurrence copy via `duplicatedNoteRef`
        // (T1) so editing one occurrence's notes never mutates a sibling's.
        // Recurrence-reopen (spec §5.2 I3): a recurring *project* task
        // (`workflowState != nil`) spawns its next occurrence in `.todo` (not
        // `.backlog`). A recurring *GTD* task (`workflowState == nil`) must spawn
        // a `nil`-workflow child — preserving 100% of pre-Projects behavior
        // (invariant I7). `.todo.forcedStatus == .open`, so `status: .open` here
        // already reconciles with the spawned workflow for both branches.
        let nextWorkflowState: WorkflowState? = task.workflowState == nil ? nil : .todo
        let carriedReminders = task.reminders.compactMap { rule -> ReminderRule? in
            if case .relative = rule { return rule }
            return nil
        }
        // `agent` assignment is pure metadata (I8) and carries to the next
        // occurrence so the queue assignment survives a recurrence.
        let next = TaskItem(
            title: task.title,
            noteRef: task.noteRef,
            dueAt: nextDate,
            startAt: nextStartAt,
            endAt: nextEndAt,
            deadlineAt: nextDeadlineAt,
            priority: task.priority,
            status: .open,
            tags: task.tags,
            recurrenceRule: recurrenceRule,
            recurrenceParentId: parentID,
            // A recurring SUBTASK spawns its next occurrence at top level rather
            // than back under the same parent (T2): otherwise the parent can never
            // `markDoneStrict` (a fresh open subtask reappears), and a
            // `cascadeComplete` snapshot leaves the new occurrence orphaned-open.
            // Project/section placement is still carried below.
            parentTaskID: nil,
            projectID: task.projectID,
            sectionID: task.sectionID,
            orderIndex: task.orderIndex,
            pinnedAsFocus: task.pinnedAsFocus,
            workflowState: nextWorkflowState,
            assignedAgent: task.agent,
            estimatedDurationSeconds: task.estimatedDurationSeconds,
            durationSource: task.durationSource
        )
        next.reminders = carriedReminders
        return next
    }
}

extension TaskItemRepository {
    /// Duplicates a recurring task's backing note for its next occurrence (T1).
    /// Each occurrence then owns its `Note` row, so a later `tasks.update(notes:)`
    /// on one occurrence can't mutate or delete a sibling's notes. Scalar content
    /// (title/blocks/plainText/role/tags) is copied; the note's derived graph edges
    /// (`containsTask` for any embedded todos) are NOT reconciled onto the copy —
    /// a recurring detail note rarely owns sub-todos, and reconciling would risk
    /// cross-linking the original's tasks (a follow-up if it ever matters).
    func duplicatedNoteRef(of sourceNoteRef: UUID?) throws -> UUID? {
        guard let sourceNoteRef else { return nil }
        var descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.id == sourceNoteRef && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        guard let source = try context.fetch(descriptor).first else { return nil }
        let copy = Note(
            title: source.title,
            contentData: source.contentData,
            plainText: source.plainText,
            role: source.role,
            tags: source.tags
        )
        let stamp = now()
        copy.createdAt = stamp
        copy.updatedAt = stamp
        context.insert(copy)
        return copy.id
    }
}
