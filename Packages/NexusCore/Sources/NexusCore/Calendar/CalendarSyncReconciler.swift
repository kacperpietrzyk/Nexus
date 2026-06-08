import Foundation
import SwiftData

/// Two-way sync between `ScheduledBlock`s and mirror events in the dedicated
/// "Nexus" calendar (spec §8 / §14). Wraps a `CalendarEventWriting` provider and
/// the `ScheduledBlockRepository`; orchestrates, never reimplements persistence.
///
/// `@MainActor` to match the SwiftData isolation across the repositories. EventKit
/// lives behind `CalendarEventWriting`, so the reconciler is fully testable with a
/// fake writer over an in-memory `ModelContainer`.
///
/// Invariants enforced (spec §14):
/// - `proposed ⇒ externalEventID == nil`; `accepted ⇒ externalEventID != nil`.
/// - At most one live mirror event per block; deletion on either side cascades.
/// - The scheduler only ever writes the "Nexus" calendar; foreign calendars are
///   read as obstacles, never written.
@MainActor
public struct CalendarSyncReconciler {
    private let context: ModelContext
    private let writer: any CalendarEventWriting
    private let blocks: ScheduledBlockRepository
    private let now: () -> Date

    public init(
        context: ModelContext,
        writer: any CalendarEventWriting,
        blocks: ScheduledBlockRepository? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.writer = writer
        self.blocks = blocks ?? ScheduledBlockRepository(context: context, now: now)
        self.now = now
    }

    // MARK: - Accept (write)

    /// Accept a proposed block: ensure the "Nexus" calendar, create a mirror event
    /// (title = task title, block `start`/`end`), store its identifier on the block,
    /// and flip the block to `accepted` (spec §8). Returns the mirror event id.
    ///
    /// Idempotent on an already-accepted block: re-accepting reuses the existing
    /// mirror event (no second event) and returns its id.
    @discardableResult
    public func accept(_ block: ScheduledBlock) async throws -> String {
        if block.status == .accepted, let existing = block.externalEventID {
            return existing
        }

        let calendarID = try await writer.ensureNexusCalendar()
        let draft = EventDraft(
            calendarID: calendarID,
            title: block.title,
            start: block.start,
            end: block.end
        )
        let eventID = try await writer.createEvent(draft)
        try blocks.markAccepted(block, externalEventID: eventID)
        return eventID
    }

    // MARK: - Read-back (observer-driven diff)

    /// Re-read the "Nexus" calendar over `[start, end)` and reconcile accepted
    /// blocks against their mirror events (spec §8). Wired to `EKEventStoreChanged`
    /// by the composition root; called directly in tests.
    ///
    /// Per block matched by `externalEventID`:
    /// - event moved (same length, different start) → update `block.start/end` only.
    /// - event resized (length changed) → update `block.start/end` AND override the
    ///   task estimate (`estimatedDurationSeconds` + `durationSource = .explicit`,
    ///   spec §5 — same as a local drag-resize).
    /// - event deleted in Apple Calendar → soft-delete the block (task returns to the
    ///   pool, spec §8). Only blocks whose times intersect the fetched window are
    ///   evaluated for deletion, so an out-of-window block is never mistaken for
    ///   deleted.
    ///
    /// External edits always win (structural last-writer-wins, spec §8): applying the
    /// store's state on read-back IS the conflict resolution — no timestamp machinery.
    /// Events not matching any block are left alone (events are not graph entities,
    /// spec §4.3 — the reconciler never creates a block from an event).
    public func reconcile(window start: Date, to end: Date) async throws {
        let calendarID = try await writer.ensureNexusCalendar()
        let snapshots = try await writer.events(inCalendar: calendarID, start: start, end: end)
        let snapshotsByID = Dictionary(snapshots.map { ($0.eventID, $0) }) { first, _ in first }

        for block in try acceptedBlocksIntersecting(start: start, to: end) {
            guard let eventID = block.externalEventID else { continue }

            if let snapshot = snapshotsByID[eventID] {
                try apply(snapshot, to: block)
            } else if let surviving = try await writer.eventSnapshot(id: eventID) {
                // Absent from the window-scoped Nexus fetch but still resolvable by
                // identifier → NOT deleted: the user moved it to another calendar
                // (or shifted its times outside the window). Apply its current state
                // rather than returning the task to the pool (R1). Absence-from-Nexus
                // alone must never be read as deletion.
                try apply(surviving, to: block)
            } else {
                // Truly gone from EventKit (no event under this identifier anywhere)
                // → the user deleted the plan in Apple Calendar. Soft-delete the block.
                try blocks.softDelete(block)
            }
        }
    }

    // MARK: - Task lifecycle

    /// Task done/deleted (spec §8): delete every mirror event and soft-delete every
    /// live block for the task. The mirror-event delete is a no-op for `proposed`
    /// blocks (no event yet) and for events already removed.
    public func handleTaskRemoved(taskID: UUID) async throws {
        let live = try blocks.blocks(for: taskID)
        for block in live {
            if let eventID = block.externalEventID {
                try await writer.deleteEvent(id: eventID)
            }
        }
        try blocks.softDeleteAll(for: taskID)
    }

    // MARK: - Diff application

    /// Apply a store snapshot onto a block (external-wins). A length change also
    /// overrides the task's duration estimate (spec §5 / §8).
    private func apply(_ snapshot: CalendarEventSnapshot, to block: ScheduledBlock) throws {
        let oldLength = block.end.timeIntervalSince(block.start)
        let newLength = snapshot.end.timeIntervalSince(snapshot.start)
        let moved = snapshot.start != block.start || snapshot.end != block.end
        guard moved else { return }

        try blocks.reschedule(block, start: snapshot.start, end: snapshot.end)

        if abs(newLength - oldLength) >= 1, newLength > 0 {
            try overrideTaskEstimate(taskID: block.taskID, seconds: Int(newLength.rounded()))
        }
    }

    /// Set the task estimate to the resized length and mark it `.explicit` so it
    /// wins the estimate cascade and feeds the history corpus (spec §5).
    private func overrideTaskEstimate(taskID: UUID, seconds: Int) throws {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        guard let task = try context.fetch(descriptor).first else { return }
        task.estimatedDurationSeconds = seconds
        task.durationSourceRaw = DurationSource.explicit.rawValue
        task.updatedAt = now()
        try context.save()
    }

    // MARK: - Queries

    /// Accepted, non-deleted blocks whose `[start, end)` intersects the window.
    private func acceptedBlocksIntersecting(start: Date, to end: Date) throws -> [ScheduledBlock] {
        let acceptedRaw = ScheduledBlockStatus.accepted.rawValue
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { block in
                block.deletedAt == nil
                    && block.statusRaw == acceptedRaw
                    && block.start < end
                    && block.end > start
            },
            sortBy: [SortDescriptor(\.start, order: .forward)]
        )
        return try context.fetch(descriptor)
    }
}
