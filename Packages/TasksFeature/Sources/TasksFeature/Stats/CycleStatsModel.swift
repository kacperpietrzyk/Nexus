import Foundation
import NexusCore

/// Pure derived stats for one cycle (Tranche 2 Plan C, spec §4.2). The
/// `ProjectExecutionModel` contract: pure & passive — no fetching, no
/// `Date.now`; the caller fetches the cycle's tasks (via
/// `CycleRepository.tasks(in:)`) and passes them in together with `now`.
/// Completion stats are derived; nothing is ever stored (no aggregates).
public enum CycleStatsModel {
    public struct Stats: Equatable, Sendable {
        public let total: Int
        public let done: Int
        /// Scope creep: tasks created after the cycle's `startAt` (spec §4.2).
        public let addedAfterStart: Int

        public var open: Int { total - done }
        public var completionFraction: Double {
            total == 0 ? 0 : Double(done) / Double(total)
        }

        public init(total: Int, done: Int, addedAfterStart: Int) {
            self.total = total
            self.done = done
            self.addedAfterStart = addedAfterStart
        }
    }

    /// Counts live, non-template tasks. "Done" is `status == .done` MINUS
    /// canceled/duplicate closures (`WorkflowState.isTerminalNonCompletion`,
    /// spec I4) — the `ProjectExecutionModel.doneCount` notion, so cycle and
    /// project completion stats agree. Soft-deleted rows are defensively
    /// ignored even though `tasks(in:)` already excludes them.
    @MainActor
    public static func stats(tasks: [TaskItem], cycleStartAt: Date) -> Stats {
        let live = tasks.filter { $0.deletedAt == nil && !$0.isTemplate }
        return Stats(
            total: live.count,
            done: live.filter { $0.status == .done && $0.workflowState?.isTerminalNonCompletion != true }.count,
            addedAfterStart: live.filter { $0.createdAt > cycleStartAt }.count
        )
    }

    public struct EndOfCyclePrompt: Equatable, Sendable {
        public let openCount: Int
        /// The move target (`CycleRepository.next(now:)`); nil when no next
        /// cycle exists — the prompt then offers guidance, never auto-creates.
        public let nextCycleID: UUID?
        public let nextCycleName: String?

        public init(openCount: Int, nextCycleID: UUID?, nextCycleName: String?) {
            self.openCount = openCount
            self.nextCycleID = nextCycleID
            self.nextCycleName = nextCycleName
        }
    }

    // Non-nil exactly when the cycle ended (`endAt < now`) but is still
    // `.active` with open tasks. This is a PROMPT decision only — the user is
    // the sole mutator; no background job ever acts on it (invariant I-C1).
    // swiftlint:disable:next function_parameter_count
    public static func endOfCyclePrompt(
        status: CycleStatus,
        endAt: Date,
        now: Date,
        openCount: Int,
        nextCycleID: UUID?,
        nextCycleName: String?
    ) -> EndOfCyclePrompt? {
        guard status == .active, endAt < now, openCount > 0 else { return nil }
        return EndOfCyclePrompt(
            openCount: openCount, nextCycleID: nextCycleID, nextCycleName: nextCycleName
        )
    }
}
