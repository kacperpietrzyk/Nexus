import Foundation

/// M2 (Motion parity): a runtime-computed "ghost" preview of one FUTURE
/// occurrence of a recurring task — `taskID` is the series' current REAL open
/// instance, `occurrenceDate` is the projected due date the preview stands in
/// for. Previews are NEVER persisted (see `RecurringSeriesProjector` doc):
/// they are derived view items the week grid renders alongside real blocks.
public struct SeriesOccurrencePreview: Equatable, Sendable, Identifiable {
    /// Recurrence series identity: `recurrenceParentId ?? task.id` of the base.
    public let seriesID: UUID
    /// The series' current open instance (a real `TaskItem`).
    public let taskID: UUID
    /// The projected due date of this future occurrence (rule time-of-day).
    public let occurrenceDate: Date
    public let start: Date
    public let end: Date
    public let title: String

    public init(seriesID: UUID, taskID: UUID, occurrenceDate: Date, start: Date, end: Date, title: String) {
        self.seriesID = seriesID
        self.taskID = taskID
        self.occurrenceDate = occurrenceDate
        self.start = start
        self.end = end
        self.title = title
    }

    /// Stable composite id (series + occurrence + chunk start) — unique even
    /// when an estimate splits into multiple sub-blocks on one day.
    public var id: String {
        "series-\(seriesID.uuidString)"
            + "-\(Int(occurrenceDate.timeIntervalSince1970))"
            + "-\(Int(start.timeIntervalSince1970))"
    }
}

/// Pure, deterministic projection of FUTURE occurrences of recurring tasks
/// into ghost preview blocks (M2, gap matrix 2026-06-11). No SwiftData
/// queries, no EventKit, no ambient clock — every input is injected.
///
/// Contract (deliberate, see plan 2026-06-11-tranche3-m2-series-scheduling):
/// - Previews are NEVER persisted as `ScheduledBlock`s. `ScheduledBlock` has
///   no occurrence identity, `planDay` wipes all live auto proposals
///   date-blind, and a block bound to the current instance would be torn down
///   or mis-targeted once completion spawns the next instance. Persisting
///   ahead-of-spawn requires a schema change (V14 candidate) — out of scope.
/// - Today and overdue belong to `DayPlanner` (today-only since S2): previews
///   start at the day after `now`.
/// - Completion-anchored rules (`ANCHOR=COMPLETION`, T1) are SKIPPED: the next
///   occurrence date depends on when the user completes the current instance,
///   so future dates are unknowable — those series stay current-instance-only.
/// - Templates never project (I-D1 inertness).
/// - Placement reuses the pure `DayScheduler` per future day, so previews
///   honor the same working window / min-max chunking / obstacle avoidance as
///   "Plan my day". Occurrences that do not fit a day are silently dropped
///   (best-effort preview, no overload reporting for future days in v1).
public struct RecurringSeriesProjector {
    private let scheduler: DayScheduler
    private let estimator: any DurationEstimator

    public init(
        scheduler: DayScheduler = DayScheduler(),
        estimator: any DurationEstimator = HeuristicDurationEstimator()
    ) {
        self.scheduler = scheduler
        self.estimator = estimator
    }

    /// Project ghost previews for every eligible recurring series.
    ///
    /// - Parameters:
    ///   - tasks: the non-deleted task universe (open + done — done siblings
    ///     feed COUNT accounting and the estimator's history corpus).
    ///   - events: calendar obstacles for the window (already visibility-filtered).
    ///   - obstacles: every live `ScheduledBlock` in the window — treated as
    ///     busy AND as the "already scheduled" dedup signal per series/day.
    ///   - prefs: working window / block sizing / `seriesPreviewHorizonDays`.
    ///   - window: the display window to clip into (e.g. the visible week).
    ///   - now: the projection instant (today is excluded).
    ///   - calendar: timezone-explicit calendar.
    ///
    /// Injecting now/calendar (the `DayScheduler.plan` convention) is what
    /// makes this pure + deterministic, so the parameter count is intrinsic.
    public func preview(  // swiftlint:disable:this function_parameter_count
        tasks: [TaskItem],
        events: [CalendarEvent],
        obstacles: [ScheduledBlock],
        prefs: CalendarPreferences,
        window: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [SeriesOccurrencePreview] {
        guard let bounds = previewBounds(prefs: prefs, window: window, now: now, calendar: calendar) else {
            return []
        }
        let live = tasks.filter { $0.deletedAt == nil && !$0.isTemplate }
        let history = live.filter {
            $0.status == .done && $0.durationSource == .explicit && $0.estimatedDurationSeconds != nil
        }
        let candidates = occurrenceCandidates(
            tasks: live, obstacles: obstacles, bounds: bounds, calendar: calendar
        )
        return place(
            candidates, events: events, obstacles: obstacles, prefs: prefs,
            history: history, calendar: calendar
        )
    }

    // MARK: - Window

    /// `[max(window.start, tomorrow), min(window.end, today + 1 + horizon))`,
    /// or nil when projection is disabled or the intersection is empty.
    private func previewBounds(
        prefs: CalendarPreferences,
        window: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let horizonDays = prefs.seriesPreviewHorizonDays
        guard horizonDays > 0 else { return nil }
        let todayStart = calendar.startOfDay(for: now)
        guard
            let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart),
            let horizonEnd = calendar.date(byAdding: .day, value: 1 + horizonDays, to: todayStart)
        else { return nil }
        let start = max(window.start, tomorrowStart)
        let end = min(window.end, horizonEnd)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    // MARK: - Occurrence derivation

    /// One projected occurrence: the series' base instance stands in for the
    /// occurrence on `occurrenceDate`'s day.
    private struct OccurrenceCandidate {
        let seriesID: UUID
        let base: TaskItem
        let occurrenceDate: Date
    }

    private func occurrenceCandidates(
        tasks: [TaskItem],
        obstacles: [ScheduledBlock],
        bounds: DateInterval,
        calendar: Calendar
    ) -> [OccurrenceCandidate] {
        var bySeries: [UUID: [TaskItem]] = [:]
        for task in tasks where task.recurrenceRule != nil {
            bySeries[task.recurrenceParentId ?? task.id, default: []].append(task)
        }
        let rruleScheduler = RRuleScheduler(calendar: calendar)
        var candidates: [OccurrenceCandidate] = []
        // Sorted series iteration → deterministic output ordering.
        for seriesID in bySeries.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let members = bySeries[seriesID] ?? []
            let openInstances = members.filter { $0.status == .open }
            guard
                let base = openInstances.max(by: { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }),
                let baseDue = base.dueAt,
                let ruleText = base.recurrenceRule,
                let rule = try? RRuleParser.parse(ruleText),
                // Completion-anchored series cannot be projected forward — the
                // next date depends on the completion instant (T1). Current
                // instance only; see the type doc.
                rule.anchor == .dueDate
            else { continue }

            var dates: [Date] = []
            // The real open instance itself, when already due on a future day
            // (the post-spawn case — DayPlanner won't touch it until its day).
            if baseDue >= bounds.start, baseDue < bounds.end {
                dates.append(baseDue)
            }
            // Mirrors `countSiblings(parentID:) + 1` (spawned siblings + root).
            let occurrencesSoFar = members.filter { $0.recurrenceParentId != nil }.count + 1
            dates += rruleScheduler.occurrences(
                after: baseDue, rule: rule, before: bounds.end, occurrencesSoFar: occurrencesSoFar
            ).filter { $0 >= bounds.start }

            let memberIDs = Set(members.map(\.id))
            for date in dates
            where !hasBlock(onDayOf: date, taskIDs: memberIDs, obstacles: obstacles, calendar: calendar) {
                candidates.append(OccurrenceCandidate(seriesID: seriesID, base: base, occurrenceDate: date))
            }
        }
        return candidates
    }

    /// True when any live block for one of `taskIDs` already touches the day
    /// of `date` — the user (or a real plan) has concretely scheduled this
    /// series there, so the ghost preview yields.
    private func hasBlock(
        onDayOf date: Date,
        taskIDs: Set<UUID>,
        obstacles: [ScheduledBlock],
        calendar: Calendar
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        return obstacles.contains { block in
            block.deletedAt == nil && taskIDs.contains(block.taskID)
                && block.start < dayEnd && block.end > dayStart
        }
    }

    // MARK: - Placement

    /// Slot-fill each future day with that day's occurrences via the pure
    /// `DayScheduler` (now = the day's midnight → the working window governs;
    /// events/obstacles are filtered per day inside the slot computer).
    private func place(  // swiftlint:disable:this function_parameter_count
        _ candidates: [OccurrenceCandidate],
        events: [CalendarEvent],
        obstacles: [ScheduledBlock],
        prefs: CalendarPreferences,
        history: [TaskItem],
        calendar: Calendar
    ) -> [SeriesOccurrencePreview] {
        let byDay = Dictionary(grouping: candidates) { calendar.startOfDay(for: $0.occurrenceDate) }
        var previews: [SeriesOccurrencePreview] = []
        for day in byDay.keys.sorted() {
            let dayCandidates = byDay[day] ?? []
            let plan = scheduler.plan(
                candidates: dayCandidates.map(\.base),
                events: events,
                accepted: obstacles,
                prefs: prefs,
                estimator: estimator,
                history: history,
                now: day,
                calendar: calendar,
                horizonDays: 1
            )
            // At most one occurrence per series per day for the supported rule
            // subset → taskID resolves the candidate unambiguously.
            let byTask = Dictionary(grouping: dayCandidates) { $0.base.id }
            for proposal in plan.proposals {
                guard let candidate = byTask[proposal.taskID]?.first else { continue }
                previews.append(
                    SeriesOccurrencePreview(
                        seriesID: candidate.seriesID,
                        taskID: candidate.base.id,
                        occurrenceDate: candidate.occurrenceDate,
                        start: proposal.start,
                        end: proposal.end,
                        title: proposal.title
                    )
                )
            }
        }
        return previews.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.id < rhs.id : lhs.start < rhs.start
        }
    }
}
