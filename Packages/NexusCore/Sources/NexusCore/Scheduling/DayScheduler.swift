import Foundation

/// Overload guardrail (spec §6): total estimated work vs total free capacity
/// across the horizon, plus the tasks that did not fit.
public struct OverloadReport: Equatable, Sendable {
    /// Sum of estimates for all candidates (seconds).
    public var totalEstimatedSeconds: Int
    /// Sum of available free time across the horizon (seconds).
    public var totalFreeSeconds: Int
    /// Candidate task IDs that could not be (fully) placed.
    public var unplacedTaskIDs: [UUID]

    public init(totalEstimatedSeconds: Int, totalFreeSeconds: Int, unplacedTaskIDs: [UUID]) {
        self.totalEstimatedSeconds = totalEstimatedSeconds
        self.totalFreeSeconds = totalFreeSeconds
        self.unplacedTaskIDs = unplacedTaskIDs
    }

    /// True when estimated work exceeds free capacity, or some candidate is
    /// unplaced. UI warns, never blocks (spec §6).
    public var isOverloaded: Bool {
        totalEstimatedSeconds > totalFreeSeconds || !unplacedTaskIDs.isEmpty
    }
}

/// A scheduler-emitted proposal — a pure, `Sendable` value object (not the
/// `@Model ScheduledBlock`, which is context-bound and non-`Sendable`). The
/// `ScheduledBlockRepository` materializes these into live blocks. Every
/// proposal is `.proposed` / `.auto` by construction (the scheduler only emits
/// proposals).
public struct BlockProposal: Equatable, Sendable {
    public var taskID: UUID
    public var start: Date
    public var end: Date
    public var title: String

    public init(taskID: UUID, start: Date, end: Date, title: String) {
        self.taskID = taskID
        self.start = start
        self.end = end
        self.title = title
    }
}

/// Output of `DayScheduler.plan`: the freshly proposed blocks plus the overload
/// guardrail. Accepted blocks are inputs, never echoed here.
public struct SchedulePlan: Equatable, Sendable {
    public var proposals: [BlockProposal]
    public var overload: OverloadReport

    public init(proposals: [BlockProposal], overload: OverloadReport) {
        self.proposals = proposals
        self.overload = overload
    }
}

/// Pure, deterministic slot-fill scheduler (spec §6 + §19.2). Zero EventKit,
/// zero UI, no RNG, no ambient clock/calendar — `now` and `calendar` are
/// injected so output is byte-stable for identical input.
///
/// Candidates are the open worklist (overdue + due-today + pinned); the caller
/// selects them. Ordering: priority desc → deadline asc → orderIndex asc →
/// `id` (total order, so ties never reorder). Accepted blocks are hard input
/// (anti-thrash) and are never moved or echoed. Estimates over `maxBlockMinutes`
/// split into sub-blocks across gaps. With `horizonDays > 1`, slot-fill spills
/// across subsequent working days; `horizonDays == 1` is the today-only case
/// (no separate code path).
public struct DayScheduler: Sendable {
    public init() {}

    // The spec (§6 / §19.2) fixes this signature: candidates, events, accepted,
    // prefs, estimator, history, now, calendar, horizon. Injecting now/calendar
    // is what makes the function pure + deterministic, so the parameter count is
    // intrinsic, not incidental.
    // swiftlint:disable:next function_body_length function_parameter_count
    public func plan(
        candidates: [TaskItem],
        events: [CalendarEvent],
        accepted: [ScheduledBlock],
        prefs: CalendarPreferences,
        estimator: DurationEstimator,
        history: [TaskItem] = [],
        now: Date,
        calendar: Calendar,
        horizonDays: Int = 1
    ) -> SchedulePlan {
        let ordered = order(candidates: candidates)
        let days = max(1, horizonDays)

        // Free slots per working day across the horizon, in chronological order.
        // A "working day" here is simply each calendar day from today; the
        // window is the working window of that day. Future days have no events
        // unless caller supplies them — events/accepted are filtered per day.
        var slots: [FreeSlot] = []
        for offset in 0..<days {
            guard let dayAnchor = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let anchor = offset == 0 ? now : calendar.startOfDay(for: dayAnchor)
            let daySlots = FreeSlotComputer.freeSlots(
                forDayContaining: anchor,
                events: events,
                acceptedBlocks: accepted,
                prefs: prefs,
                calendar: calendar
            )
            // On day 0, the working window starts at the later of workday-start
            // and `now` so we never propose blocks in the past.
            let clamped = daySlots.compactMap { slot -> FreeSlot? in
                let start = offset == 0 ? max(slot.start, now) : slot.start
                guard slot.end.timeIntervalSince(start) >= TimeInterval(prefs.minBlockMinutes * 60) else { return nil }
                return FreeSlot(start: start, end: slot.end)
            }
            slots.append(contentsOf: clamped)
        }

        var remaining = slots
        var proposals: [BlockProposal] = []
        var unplaced: [UUID] = []
        var totalEstimated = 0
        let maxBlockSeconds = TimeInterval(prefs.maxBlockMinutes * 60)
        let minBlockSeconds = TimeInterval(prefs.minBlockMinutes * 60)

        for task in ordered {
            let estimate = estimator.estimate(for: task, history: history)
            let estimatedSeconds = max(prefs.minBlockMinutes * 60, estimate.seconds)
            totalEstimated += estimatedSeconds

            var needed = TimeInterval(estimatedSeconds)
            var placedAny = false
            var fullyPlaced = true

            while needed >= minBlockSeconds {
                let chunk = min(needed, maxBlockSeconds)
                guard let placement = placeChunk(of: chunk, into: &remaining, minBlockSeconds: minBlockSeconds) else {
                    fullyPlaced = false
                    break
                }
                proposals.append(
                    BlockProposal(
                        taskID: task.id,
                        start: placement.start,
                        end: placement.end,
                        title: task.title
                    )
                )
                placedAny = true
                needed -= placement.end.timeIntervalSince(placement.start)
            }

            if !fullyPlaced || !placedAny {
                unplaced.append(task.id)
            }
        }

        let totalFree = slots.reduce(0) { $0 + Int($1.duration) }
        return SchedulePlan(
            proposals: proposals,
            overload: OverloadReport(
                totalEstimatedSeconds: totalEstimated,
                totalFreeSeconds: totalFree,
                unplacedTaskIDs: unplaced
            )
        )
    }

    // MARK: - Ordering

    /// Total order (spec §6): priority desc → deadline asc (nil last) →
    /// orderIndex asc (nil last) → id. The `id` tiebreaker guarantees identical
    /// input → identical output even when every other key ties.
    func order(candidates: [TaskItem]) -> [TaskItem] {
        candidates.sorted { lhs, rhs in
            if lhs.priorityRaw != rhs.priorityRaw {
                return lhs.priorityRaw > rhs.priorityRaw
            }
            let lDeadline = lhs.deadlineAt ?? Date.distantFuture
            let rDeadline = rhs.deadlineAt ?? Date.distantFuture
            if lDeadline != rDeadline {
                return lDeadline < rDeadline
            }
            let lOrder = lhs.orderIndex ?? Double.greatestFiniteMagnitude
            let rOrder = rhs.orderIndex ?? Double.greatestFiniteMagnitude
            if lOrder != rOrder {
                return lOrder < rOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Placement

    /// Place a chunk of `seconds` into the first free slot that fits, consuming
    /// the front of that slot. Returns the placed interval, or nil if no slot is
    /// large enough.
    private func placeChunk(
        of seconds: TimeInterval,
        into slots: inout [FreeSlot],
        minBlockSeconds: TimeInterval
    ) -> (start: Date, end: Date)? {
        for index in slots.indices where slots[index].duration >= seconds {
            let slot = slots[index]
            let start = slot.start
            let end = start.addingTimeInterval(seconds)
            // Consume the front; keep the tail only if it remains usable.
            if slot.end.timeIntervalSince(end) >= minBlockSeconds {
                slots[index] = FreeSlot(start: end, end: slot.end)
            } else {
                slots.remove(at: index)
            }
            return (start, end)
        }
        return nil
    }
}
