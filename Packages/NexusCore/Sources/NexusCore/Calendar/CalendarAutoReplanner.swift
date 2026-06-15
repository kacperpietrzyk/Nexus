import Foundation
import SwiftData

/// M1 auto-replan pipeline (gap matrix 2026-06-11), run after every
/// `EKEventStoreChanged`: reconcile external edits → conflict scan →
/// regenerate broken auto proposals → report what remains.
///
/// Anti-thrash contract (spec §1/§14, deliberately preserved):
/// - A store change NEVER initiates planning — proposals regenerate only when
///   an existing auto proposal now collides with an obstacle.
/// - Accepted and manual blocks are NEVER moved. They are reported as
///   `protectedBlockIDs`; the UI surfaces a non-blocking "Replan" affordance.
///
/// `@MainActor` to match SwiftData isolation across the repositories (the
/// `CalendarSyncReconciler` / `DayPlanner` pattern). Deterministic and
/// testable: events, prefs, `now`, and `calendar` are injected; EventKit lives
/// behind the reconciler's writer.
@MainActor
public struct CalendarAutoReplanner {
    /// What the pipeline did and what is left for the user to decide.
    public struct Outcome {
        /// Post-pipeline conflicts. After a regenerate pass the auto list is
        /// empty by construction; what remains is the protected set.
        public let report: BlockConflictReport
        /// True when broken auto proposals were regenerated via `planDay`.
        public let replanned: Bool
        /// Overload guardrail from the regenerate pass, when it ran.
        public let overload: OverloadReport?

        public init(report: BlockConflictReport, replanned: Bool, overload: OverloadReport?) {
            self.report = report
            self.replanned = replanned
            self.overload = overload
        }
    }

    private let context: ModelContext
    private let reconciler: CalendarSyncReconciler?
    private let planner: DayPlanner
    private let blocks: ScheduledBlockRepository

    public init(
        context: ModelContext,
        reconciler: CalendarSyncReconciler? = nil,
        planner: DayPlanner? = nil,
        blocks: ScheduledBlockRepository? = nil
    ) {
        self.context = context
        self.reconciler = reconciler
        self.planner = planner ?? DayPlanner(context: context)
        self.blocks = blocks ?? ScheduledBlockRepository(context: context)
    }

    /// Run the pipeline over TODAY (the planner is today-only since S2).
    /// `events` are the caller's already-visibility-filtered obstacles for the
    /// day (the same set `planDay` would receive).
    public func handleStoreChange(
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        now: Date,
        calendar: Calendar
    ) async throws -> Outcome {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        // 1. Apply external edits to accepted blocks first (read-back wins,
        //    spec §8). No-op without write access (reconciler == nil).
        if let reconciler {
            try await reconciler.reconcile(window: dayStart, to: dayEnd)
        }

        // 2. Conflict scan over today's live blocks.
        let liveBlocks = try blocks.blocks(from: dayStart, to: dayEnd)
        let report = BlockConflictDetector.detect(blocks: liveBlocks, events: events)

        // 3. Auto proposals are ephemeral by design → regenerate the whole
        //    proposal set around the new obstacles, but ONLY when an existing
        //    proposal actually broke (never initiate planning).
        var overload: OverloadReport?
        var replanned = false
        if !report.autoProposedBlockIDs.isEmpty {
            let result = try planner.planDay(events: events, prefs: prefs, now: now, calendar: calendar)
            overload = result.overload
            replanned = true
        }

        // 4. Re-scan: regenerated proposals are conflict-free by construction;
        //    what remains is the protected set the UI surfaces.
        let after = try blocks.blocks(from: dayStart, to: dayEnd)
        let finalReport = BlockConflictDetector.detect(blocks: after, events: events)
        return Outcome(report: finalReport, replanned: replanned, overload: overload)
    }
}
