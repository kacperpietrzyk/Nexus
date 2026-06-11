import Foundation
import SwiftData

/// Orchestrates the "Plan my day" ritual (spec §6 / §10): gather open candidates,
/// read calendar obstacles + already-accepted blocks, run the pure `DayScheduler`,
/// and persist the resulting `proposed` blocks. Returns the overload guardrail so
/// the UI can warn (never block, spec §6).
///
/// Lives in NexusCore so both the Calendar surface and the Tasks Today rail reuse
/// it without importing each other (feature modules never cross-import). The pure
/// scheduling decisions stay in `DayScheduler` / `DayPlanCandidates`; this type only
/// wires fetch → schedule → persist.
///
/// `@MainActor` to match SwiftData isolation across the repositories. Events are
/// supplied by the caller (already fetched from the `CalendarEventProviding`) so this
/// orchestrator stays EventKit-free and unit-testable with an in-memory store.
@MainActor
public struct DayPlanner {
    private let context: ModelContext
    private let blocks: ScheduledBlockRepository
    private let scheduler: DayScheduler
    private let estimator: DurationEstimator

    public init(
        context: ModelContext,
        blocks: ScheduledBlockRepository? = nil,
        scheduler: DayScheduler = DayScheduler(),
        estimator: DurationEstimator = HeuristicDurationEstimator()
    ) {
        self.context = context
        self.blocks = blocks ?? ScheduledBlockRepository(context: context)
        self.scheduler = scheduler
        self.estimator = estimator
    }

    /// Result of a planning pass: the freshly persisted proposals and the overload
    /// guardrail. `@MainActor`-bound (carries `@Model` blocks, which are
    /// context-isolated, not `Sendable`).
    @MainActor
    public struct Result {
        public let proposals: [ScheduledBlock]
        public let overload: OverloadReport

        public init(proposals: [ScheduledBlock], overload: OverloadReport) {
            self.proposals = proposals
            self.overload = overload
        }
    }

    /// Plan the day (or `horizonDays`): clear stale `auto`/`proposed` blocks, run the
    /// scheduler over fresh candidates, and persist new proposals. Accepted blocks are
    /// inputs (never moved). Returns the persisted proposals + overload report.
    ///
    /// - Parameters:
    ///   - events: calendar obstacles in the horizon (caller fetched from the provider).
    ///   - prefs: working-window / block-size preferences.
    ///   - now: planning instant.
    ///   - calendar: timezone-explicit calendar.
    ///   - horizonDays: planning horizon (default 1 = today only).
    @discardableResult
    public func planDay(
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        now: Date,
        calendar: Calendar,
        horizonDays: Int = 1
    ) throws -> Result {
        // Clear stale auto proposals so a re-plan never duplicates (anti-thrash:
        // accepted blocks are untouched, only auto/proposed are regenerated).
        try clearStaleProposals()

        let openTasks = try fetchOpenTasks()
        let candidates = DayPlanCandidates.select(from: openTasks, now: now, calendar: calendar)
        let history = openTasks.filter {
            $0.status == .done && $0.durationSource == .explicit && $0.estimatedDurationSeconds != nil
        }
        let accepted = try obstacleBlocks(now: now, calendar: calendar, horizonDays: horizonDays)

        let plan = scheduler.plan(
            candidates: candidates,
            events: events,
            accepted: accepted,
            prefs: prefs,
            estimator: estimator,
            history: history,
            now: now,
            calendar: calendar,
            horizonDays: horizonDays
        )

        var persisted: [ScheduledBlock] = []
        for proposal in plan.proposals {
            persisted.append(try blocks.persistProposal(proposal))
        }
        return Result(proposals: persisted, overload: plan.overload)
    }

    // MARK: - Fetch helpers

    private func fetchOpenTasks() throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        return try context.fetch(descriptor)
    }

    /// Hard obstacles for the slot-fill: accepted blocks PLUS manual-origin
    /// proposals — both are user commitments the scheduler plans around and
    /// never moves (anti-thrash, spec §1/§14).
    private func obstacleBlocks(now: Date, calendar: Calendar, horizonDays: Int) throws -> [ScheduledBlock] {
        let start = calendar.startOfDay(for: now)
        let days = max(1, horizonDays)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let acceptedRaw = ScheduledBlockStatus.accepted.rawValue
        let manualRaw = ScheduledBlockOrigin.manual.rawValue
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { block in
                block.deletedAt == nil
                    && (block.statusRaw == acceptedRaw || block.originRaw == manualRaw)
                    && block.start < end
                    && block.end > start
            },
            sortBy: [SortDescriptor(\.start, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Soft-delete live **auto-origin** `proposed` blocks so a re-plan
    /// regenerates a clean set. Accepted blocks (which mirror real events) and
    /// manual-origin proposals (hand-placed by the user, origin preserved
    /// across re-plans per `ScheduledBlockOrigin.manual`) are never touched.
    private func clearStaleProposals() throws {
        let proposedRaw = ScheduledBlockStatus.proposed.rawValue
        let autoRaw = ScheduledBlockOrigin.auto.rawValue
        let descriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate {
                $0.deletedAt == nil && $0.statusRaw == proposedRaw && $0.originRaw == autoRaw
            }
        )
        for block in try context.fetch(descriptor) {
            try blocks.softDelete(block)
        }
    }
}
