import Foundation
import SwiftData

/// Reconciliation of the optional `WorkflowState` machine against the canonical
/// `TaskStatus` (Projects tier, spec §5). `status` stays the SOLE source of truth
/// for every existing consumer (TodayQuery, UpcomingQuery, recurrence-reopen,
/// completion + `lastCompletedAt`, AWAITING-YOU, widgets, notifications);
/// `workflowState` is a one-directional overlay mapped deterministically per
/// table 5.1. This is the single write path that may set `workflowStateRaw` —
/// the model exposes no raw setter to UI/MCP.
///
/// Invariants enforced here:
/// - **I1.** A task with `workflowState != nil` always has `status` per table 5.1
///   (snooze excepted, see I2). The repository never leaves a divergence.
/// - **I2.** `snoozed` is orthogonal scheduling, not a work state: the open-group
///   states force `.snoozed` while a snooze is active and `.open` otherwise; the
///   target `workflowState` is unchanged.
/// - **I4.** `canceled`/`duplicate` force `status = .done` WITHOUT `lastCompletedAt`
///   (excluded from completion-stats) and spawn no recurrence (terminal closure).
@MainActor
extension TaskItemRepository {
    /// Sets `task.workflowState` and reconciles `status` per spec §5.1
    /// (one-directional `workflowState ⇒ status`). This is the only sanctioned
    /// way to mutate the machine; raw `status` is never set directly for a
    /// project task.
    ///
    /// Branches:
    /// - `.done` delegates to `markDone` so completion is identical whether
    ///   reached via the machine or the existing path (sets `lastCompletedAt`,
    ///   spawns the next recurrence, dispatches notifications) plus stamps the
    ///   `.done` workflow.
    /// - `.canceled`/`.duplicate` are terminal non-completions (I4): `status =
    ///   .done`, `lastCompletedAt` untouched, no recurrence spawn, snooze cleared.
    /// - open-group (`backlog`/`todo`/`inProgress`/`inReview`) forces
    ///   `.snoozed` if a snooze is active (I2) else `.open`.
    public func setWorkflowState(_ state: WorkflowState, on task: TaskItem) throws {
        // I-D1: the workflow machine is a completion/queue surface; templates are
        // inert blueprints — `instantiate` resets workflow to `.todo` instead.
        // Placed BEFORE the activity record: templates emit no activity events.
        guard !task.isTemplate else { return }
        // Record the transition ONCE, with the pre-mutation raw (spec §4.1).
        // Skip when unchanged: besides being noise, an unchanged `.done` would
        // hit `markDone`'s early return (no save) and strand an inserted entry
        // in the context — violating ride-the-host-save (I-B1). Known accepted
        // edge (pre-existing quirk, same blast radius as the workflow stamp
        // itself): `nil → .done` on a GTD task ALREADY completed via `markDone`
        // records `workflowChanged` but strands it until the next save.
        if task.workflowStateRaw != state.rawValue {
            activity.recordChange(
                .workflowChanged, itemID: task.id, itemKind: .task,
                old: task.workflowStateRaw, new: state.rawValue
            )
        }
        switch state {
        case .done:
            // Stamp the workflow first so `completeTask`'s "already non-nil"
            // gate sees a project task and the spawned occurrence inherits the
            // machine; `markDone` then drives status/lastCompletedAt/spawn.
            task.workflowStateRaw = WorkflowState.done.rawValue
            try markDone(task)

        case .canceled, .duplicate:
            try closeTerminal(task, as: state)

        case .backlog, .todo, .inProgress, .inReview:
            try openInQueue(task, as: state)
        }
    }

    /// Terminal closure (`canceled`/`duplicate`): `status = .done` WITHOUT
    /// `lastCompletedAt`, no recurrence spawn, snooze cleared (spec §5.2 I4).
    private func closeTerminal(_ task: TaskItem, as state: WorkflowState) throws {
        task.workflowStateRaw = state.rawValue
        task.statusRaw = TaskStatus.done.rawValue
        task.snoozedUntil = nil
        task.updatedAt = now()
        try context.save()
        // Cancel any pending notifications for this now-closed task; nothing is
        // scheduled (terminal). Mirrors completion's notifier teardown.
        let notifier = notifications
        let taskID = task.id
        Task { @MainActor in await notifier.cancel(taskID: taskID) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }

    /// Open-group reconciliation (spec §5.1): forces `.snoozed` while a snooze is
    /// active (I2 — snooze suspends the mapping for its duration, workflow
    /// unchanged), `.open` otherwise.
    private func openInQueue(_ task: TaskItem, as state: WorkflowState) throws {
        task.workflowStateRaw = state.rawValue
        let snoozeActive = (task.snoozedUntil.map { $0 > now() }) ?? false
        task.statusRaw = (snoozeActive ? TaskStatus.snoozed : TaskStatus.open).rawValue
        if !snoozeActive {
            task.snoozedUntil = nil
        }
        task.updatedAt = now()
        try context.save()
        let notifier = notifications
        let rescheduled = task
        Task { @MainActor in try? await notifier.reschedule(rescheduled) }
        let pusher = snapshotPusher
        Task { @MainActor in await pusher() }
    }
}
