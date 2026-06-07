import Foundation

/// How much breathing room a task has before its deadline (spec §19.1).
public enum DeadlineRiskSeverity: String, Sendable, Equatable, CaseIterable {
    /// Comfortable slack.
    case onTrack
    /// Slack is positive but thin.
    case tight
    /// Projected to miss — work due ≥ available free time before the deadline.
    case atRisk
}

/// A forward-looking risk projection for a single task with a deadline
/// (spec §19.1). Pure signal — never an auto-action.
public struct DeadlineRisk: Equatable, Sendable {
    public var taskID: UUID
    public var severity: DeadlineRiskSeverity
    /// Free hours before the deadline minus the estimated work that must precede
    /// or coincide with this task. Negative ⇒ projected to miss.
    public var projectedSlackHours: Double
    /// When the user should start to stay on track. nil when `onTrack` (no
    /// pressure to surface).
    public var suggestedStartBy: Date?

    public init(
        taskID: UUID,
        severity: DeadlineRiskSeverity,
        projectedSlackHours: Double,
        suggestedStartBy: Date?
    ) {
        self.taskID = taskID
        self.severity = severity
        self.projectedSlackHours = projectedSlackHours
        self.suggestedStartBy = suggestedStartBy
    }
}

/// Pure, deterministic forward projection of deadline risk (spec §19.1). Zero
/// EventKit / UI / RNG; `now` and `calendar` injected. Produces a signal only —
/// it never schedules or moves anything (spec principle: suggestive, not
/// aggressive).
///
/// For each open task `T` with `deadlineAt` inside `horizon`, the competing set
/// is every open task with `priority >= T.priority` AND `deadlineAt <= T`'s
/// deadline (including `T` itself). `projectedSlack = freeHoursUntil(deadline) −
/// Σ estimates(competing set)`. Severity is thresholded on slack hours.
public struct DeadlineRiskAnalyzer: Sendable {
    /// Slack (hours) at or above which a task is `onTrack`.
    public let onTrackSlackHours: Double
    /// Slack (hours) at or above which a task is `tight` (below `onTrack`).
    public let tightSlackHours: Double

    public init(onTrackSlackHours: Double = 2.0, tightSlackHours: Double = 0.0) {
        self.onTrackSlackHours = onTrackSlackHours
        self.tightSlackHours = tightSlackHours
    }

    // Spec §19.1 fixes the inputs (tasks, events, prefs, estimator, history,
    // horizon, now, calendar); now/calendar injection is what keeps it pure.
    // swiftlint:disable:next function_parameter_count
    public func analyze(
        tasks: [TaskItem],
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        estimator: DurationEstimator,
        history: [TaskItem] = [],
        horizon: TimeInterval,
        now: Date,
        calendar: Calendar
    ) -> [DeadlineRisk] {
        let horizonEnd = now.addingTimeInterval(horizon)
        let openTasks = tasks.filter { $0.status == .open && $0.deletedAt == nil }

        // Pre-compute each open task's estimate once (deterministic).
        var estimateByID: [UUID: Int] = [:]
        for task in openTasks {
            estimateByID[task.id] = max(0, estimator.estimate(for: task, history: history).seconds)
        }

        // Tasks that get a risk entry: those with a deadline inside the horizon.
        let deadlineTasks =
            openTasks
            .filter { task in
                guard let deadline = task.deadlineAt else { return false }
                return deadline > now && deadline <= horizonEnd
            }
            .sorted { lhs, rhs in
                // Deterministic order; output order is stable for identical input.
                let lDeadline = lhs.deadlineAt ?? .distantFuture
                let rDeadline = rhs.deadlineAt ?? .distantFuture
                if lDeadline != rDeadline { return lDeadline < rDeadline }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        return deadlineTasks.map { task in
            risk(for: task, openTasks: openTasks, estimateByID: estimateByID, events: events, prefs: prefs, now: now, calendar: calendar)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func risk(
        for task: TaskItem,
        openTasks: [TaskItem],
        estimateByID: [UUID: Int],
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        now: Date,
        calendar: Calendar
    ) -> DeadlineRisk {
        guard let deadline = task.deadlineAt else {
            return DeadlineRisk(taskID: task.id, severity: .onTrack, projectedSlackHours: 0, suggestedStartBy: nil)
        }

        // Competing set: priority >= T AND deadline <= T's deadline (incl. T).
        let competingSeconds = openTasks.reduce(0) { partial, other in
            guard let otherDeadline = other.deadlineAt else { return partial }
            guard other.priorityRaw >= task.priorityRaw, otherDeadline <= deadline else { return partial }
            return partial + (estimateByID[other.id] ?? 0)
        }

        let freeSeconds = freeSecondsBetween(now: now, deadline: deadline, events: events, prefs: prefs, calendar: calendar)
        let slackSeconds = Double(freeSeconds - competingSeconds)
        let slackHours = slackSeconds / 3600.0

        let severity: DeadlineRiskSeverity
        if slackHours >= onTrackSlackHours {
            severity = .onTrack
        } else if slackHours >= tightSlackHours {
            severity = .tight
        } else {
            severity = .atRisk
        }

        // suggestedStartBy: when the competing work must begin to finish by the
        // deadline = deadline − competingWork. Working time is approximated as
        // wall-clock here (the UI renders this as guidance, not a scheduled
        // block). Clamped to `>= now`: an already-overcommitted task projects a
        // start time in the past, so we surface "start now" rather than a
        // nonsensical past/overnight instant. nil when onTrack.
        let suggestedStartBy: Date?
        if severity == .onTrack {
            suggestedStartBy = nil
        } else {
            suggestedStartBy = max(now, deadline.addingTimeInterval(-Double(competingSeconds)))
        }

        return DeadlineRisk(
            taskID: task.id,
            severity: severity,
            projectedSlackHours: (slackHours * 100).rounded() / 100,
            suggestedStartBy: suggestedStartBy
        )
    }

    /// Sum of free working time (per `prefs`) across every working day from `now`
    /// up to `deadline`. Events are obstacles; accepted blocks are not consulted
    /// here (risk is about raw deadline feasibility, not the current plan).
    private func freeSecondsBetween(
        now: Date,
        deadline: Date,
        events: [CalendarEvent],
        prefs: CalendarPreferences,
        calendar: Calendar
    ) -> Int {
        guard deadline > now else { return 0 }
        var total = 0
        let spanDays =
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: now),
                to: calendar.startOfDay(for: deadline)
            ).day ?? 0
        let dayCount = max(1, spanDays + 1)
        for offset in 0..<dayCount {
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let anchor = offset == 0 ? now : calendar.startOfDay(for: date)
            let slots = FreeSlotComputer.freeSlots(
                forDayContaining: anchor,
                events: events,
                acceptedBlocks: [],
                prefs: prefs,
                calendar: calendar
            )
            for slot in slots {
                let start = max(slot.start, offset == 0 ? now : slot.start)
                let end = min(slot.end, deadline)
                if end > start {
                    total += Int(end.timeIntervalSince(start))
                }
            }
        }
        return total
    }
}
