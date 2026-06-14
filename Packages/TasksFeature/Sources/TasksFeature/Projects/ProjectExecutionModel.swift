import Foundation
import NexusCore

/// Pure derived-data helpers feeding the liquid-glass Projects/Execution screen
/// (`liquid_productivity_design_system/docs/07_MODULE_PROJECTS.md`): milestones
/// timeline, progress, health gauge, delivery risks, and a recent-activity feed.
///
/// Design contract:
/// - **Pure & passive** — no fetching, no `Date.now`; the screen fetches live
///   (non-deleted) entities and passes them in together with `now`. Soft-deleted
///   rows (`deletedAt != nil`) are defensively ignored anyway.
/// - **Snapshot DTO outputs** — plain `Equatable + Sendable` value types
///   (UUID/String/Date), never `@Model` references, so results can cross
///   actor/`task` boundaries and diff cheaply in SwiftUI.
/// - **Aligned semantics** — "done" is `TaskItem.status == .done`, the same
///   notion `LiquidTodayModel.projectProgress` and the Kanban board use
///   (`WorkflowState.forcedStatus` keeps workflow tasks consistent with it).
public enum ProjectExecutionModel {

    // MARK: - Product heuristics (named constants)

    /// Open tasks whose overdue share *exceeds* this are at risk (strict `>`,
    /// so exactly 10% overdue is still on track). Product heuristic, not a law.
    public static let atRiskOverdueRatio = 0.10
    /// Open tasks whose overdue share *exceeds* this are off track (strict `>`,
    /// so exactly 30% overdue is "only" at risk). Product heuristic.
    public static let offTrackOverdueRatio = 0.30
    /// A hard deadline within this window (inclusive) on an open task flags
    /// at-risk; a deadline already behind `now` flags off-track.
    public static let deadlineWarningWindow: TimeInterval = 48 * 3_600

    // MARK: - Milestones

    /// Lifecycle of a milestone on the execution timeline.
    public enum MilestoneState: Equatable, Sendable {
        case completed
        case inProgress
        case upcoming
    }

    /// Snapshot of one project `Section` rendered as a timeline milestone.
    public struct Milestone: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let state: MilestoneState

        public init(id: UUID, title: String, state: MilestoneState) {
            self.id = id
            self.title = title
            self.state = state
        }
    }

    /// Derives the milestone timeline from a project's sections, ordered by
    /// `Section.orderIndex` (the same axis the board/section UI sorts on).
    ///
    /// State rules per section:
    /// - `.completed` — has ≥1 live task and every one is done. Note that
    ///   `canceled`/`duplicate` workflow closures force `status == .done`, so a
    ///   section closed out that way counts as completed here, mirroring the
    ///   board's "closed lane" semantics.
    /// - `.inProgress` — not all done, but some work moved: any task done OR any
    ///   task in an in-flight workflow lane (`inProgress`/`inReview`).
    ///   `backlog`/`todo` are queued, not in-flight.
    /// - `.upcoming` — everything else, including empty sections.
    ///
    /// Callers must pass only live (non-deleted) sections — this function does
    /// not filter `Section.deletedAt` (tasks are defensively filtered, sections
    /// are not).
    /// (`Section` here is `NexusCore.Section` — this file imports no SwiftUI,
    /// so the bare name is unambiguous; UI callers go through `ProjectSection`.)
    public static func milestones(
        sections: [Section],
        tasksBySection: [UUID: [TaskItem]]
    ) -> [Milestone] {
        sections
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { section in
                let tasks = live(tasksBySection[section.id] ?? [])
                return Milestone(
                    id: section.id,
                    title: section.name,
                    state: milestoneState(for: tasks)
                )
            }
    }

    private static func milestoneState(for tasks: [TaskItem]) -> MilestoneState {
        guard !tasks.isEmpty else { return .upcoming }
        let doneCount = tasks.count(where: { $0.status == .done })
        if doneCount == tasks.count { return .completed }
        let anyInFlight = tasks.contains { task in
            task.workflowState == .inProgress || task.workflowState == .inReview
        }
        return (doneCount > 0 || anyInFlight) ? .inProgress : .upcoming
    }

    // MARK: - Progress

    /// done/total over the live tasks, in `[0, 1]`; empty input is `0`. Counts
    /// the same way as `LiquidTodayModel.projectProgress` — a separate
    /// implementation that must be kept aligned manually if either definition
    /// of "project progress" changes.
    public static func progress(tasks: [TaskItem]) -> Double {
        let tasks = live(tasks)
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.count(where: { $0.status == .done })) / Double(tasks.count)
    }

    // MARK: - Stats

    /// KPI snapshot for the Overview header row. All counts over live tasks;
    /// `overdue` counts only open (not-done) tasks whose `dueAt` is behind `now`
    /// (same "overdue" notion as `health`). `progress` matches `progress(tasks:)`.
    public struct ProjectStats: Equatable, Sendable {
        public let total: Int
        public let open: Int
        public let done: Int
        public let overdue: Int
        public let progress: Double

        public init(total: Int, open: Int, done: Int, overdue: Int, progress: Double) {
            self.total = total
            self.open = open
            self.done = done
            self.overdue = overdue
            self.progress = progress
        }
    }

    public static func stats(tasks: [TaskItem], now: Date) -> ProjectStats {
        let live = live(tasks)
        let done = live.count(where: { $0.status == .done })
        let open = live.count - done
        let overdue = live.count(where: { $0.status != .done && isOverdue($0, now: now) })
        return ProjectStats(
            total: live.count,
            open: open,
            done: done,
            overdue: overdue,
            progress: progress(tasks: live)
        )
    }

    // MARK: - Health

    /// Health gauge classification (spec: On Track / At Risk / Off Track).
    public enum ProjectHealth: Equatable, Sendable {
        case onTrack
        case atRisk
        case offTrack
    }

    /// Classifies delivery health from the open (not-done) live tasks:
    /// - `.offTrack` — overdue share of open tasks > `offTrackOverdueRatio`, OR
    ///   any open task's `deadlineAt` is already behind `now`.
    /// - `.atRisk` — overdue share > `atRiskOverdueRatio`, OR any open task's
    ///   `deadlineAt` falls within `deadlineWarningWindow` of `now` (inclusive).
    /// - `.onTrack` — otherwise; no open tasks (empty/all-done) is on track.
    ///
    /// "Overdue" = `dueAt < now`. Snoozed tasks are still open work.
    public static func health(tasks: [TaskItem], now: Date) -> ProjectHealth {
        let open = live(tasks).filter { $0.status != .done }
        guard !open.isEmpty else { return .onTrack }

        let overdueRatio = Double(open.count(where: { isOverdue($0, now: now) })) / Double(open.count)
        let deadlinePassed = open.contains { deadlineUrgency($0, now: now) == .passed }
        if overdueRatio > offTrackOverdueRatio || deadlinePassed { return .offTrack }

        let deadlineLooming = open.contains { deadlineUrgency($0, now: now) == .withinWindow }
        if overdueRatio > atRiskOverdueRatio || deadlineLooming { return .atRisk }

        return .onTrack
    }

    // MARK: - Risks

    /// What put a task on the risk list. (No "blocked" kind: the workflow
    /// machine has no blocked-ish state — see `WorkflowState`.)
    public enum RiskKind: Equatable, Sendable {
        case overdue
        case deadline
    }

    /// Snapshot of one at-risk task for the risk cards. At most one risk per
    /// task; `id == taskID`.
    public struct ProjectRisk: Identifiable, Equatable, Sendable {
        public let taskID: UUID
        public let title: String
        public let kind: RiskKind
        public let dueAt: Date?
        public let deadlineAt: Date?

        public var id: UUID { taskID }

        public init(taskID: UUID, title: String, kind: RiskKind, dueAt: Date?, deadlineAt: Date?) {
            self.taskID = taskID
            self.title = title
            self.kind = kind
            self.dueAt = dueAt
            self.deadlineAt = deadlineAt
        }
    }

    /// Open live tasks that are delivery risks: a hard deadline passed or within
    /// `deadlineWarningWindow` (kind `.deadline` — it outranks overdue when both
    /// apply, drop-dead beats soft-due), else overdue `dueAt` (kind `.overdue`).
    /// Sorted most urgent first (earliest qualifying anchor date; title then id
    /// break ties deterministically), capped at `limit`.
    public static func risks(tasks: [TaskItem], now: Date, limit: Int = 5) -> [ProjectRisk] {
        let open = live(tasks).filter { $0.status != .done }

        let scored: [(risk: ProjectRisk, anchor: Date)] = open.compactMap { task in
            if deadlineUrgency(task, now: now) != .none, let deadlineAt = task.deadlineAt {
                return (
                    ProjectRisk(taskID: task.id, title: task.title, kind: .deadline, dueAt: task.dueAt, deadlineAt: deadlineAt),
                    deadlineAt
                )
            }
            if isOverdue(task, now: now), let dueAt = task.dueAt {
                return (
                    ProjectRisk(taskID: task.id, title: task.title, kind: .overdue, dueAt: dueAt, deadlineAt: task.deadlineAt),
                    dueAt
                )
            }
            return nil
        }

        return
            scored
            .sorted {
                if $0.anchor != $1.anchor { return $0.anchor < $1.anchor }
                if $0.risk.title != $1.risk.title { return $0.risk.title < $1.risk.title }
                // UUID-order is a stability guarantee only (deterministic output
                // for equal anchor+title), not a semantic ranking.
                return $0.risk.taskID.uuidString < $1.risk.taskID.uuidString
            }
            .prefix(limit)
            .map(\.risk)
    }

    // MARK: - Activity

    /// What an activity feed row records.
    public enum ActivityKind: Equatable, Sendable {
        case taskCompleted
        case taskCreated
        case noteUpdated
    }

    /// One row of the derived activity feed. `id` is composite
    /// (`kind` + source UUID) because one task can legitimately appear twice
    /// (created and completed).
    public struct ActivityEntry: Identifiable, Equatable, Sendable {
        public let id: String
        public let timestamp: Date
        public let kind: ActivityKind
        public let title: String

        public init(id: String, timestamp: Date, kind: ActivityKind, title: String) {
            self.id = id
            self.timestamp = timestamp
            self.kind = kind
            self.title = title
        }
    }

    /// Derived recent-activity feed — a best-effort reconstruction from entity
    /// timestamps, NOT an audit log (the schema records no event history):
    /// - task completed — done tasks, stamped `lastCompletedAt` (falls back to
    ///   `updatedAt` when the repository never stamped one). `canceled`/
    ///   `duplicate` closures are excluded — they are not completed work
    ///   (`WorkflowState.isTerminalNonCompletion`).
    /// - task created — every live task, stamped `createdAt` (the `limit` cap on
    ///   the merged feed is the recency window).
    /// - note updated — stamped `updatedAt`.
    /// Merged newest-first (kind rank then id break exact-timestamp ties
    /// deterministically), capped at `limit`.
    public static func activity(tasks: [TaskItem], notes: [Note], limit: Int = 8) -> [ActivityEntry] {
        let tasks = live(tasks)
        var entries: [ActivityEntry] = []

        for task in tasks {
            if task.status == .done, task.workflowState?.isTerminalNonCompletion != true {
                entries.append(
                    ActivityEntry(
                        id: "completed:\(task.id.uuidString)",
                        timestamp: task.lastCompletedAt ?? task.updatedAt,
                        kind: .taskCompleted,
                        title: task.title
                    )
                )
            }
            entries.append(
                ActivityEntry(
                    id: "created:\(task.id.uuidString)",
                    timestamp: task.createdAt,
                    kind: .taskCreated,
                    title: task.title
                )
            )
        }

        for note in notes where note.deletedAt == nil {
            entries.append(
                ActivityEntry(
                    id: "note:\(note.id.uuidString)",
                    timestamp: note.updatedAt,
                    kind: .noteUpdated,
                    title: note.title
                )
            )
        }

        return Array(
            entries
                .sorted {
                    if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
                    if $0.kind != $1.kind { return rank($0.kind) < rank($1.kind) }
                    return $0.id < $1.id
                }
                .prefix(limit)
        )
    }

    private static func rank(_ kind: ActivityKind) -> Int {
        switch kind {
        case .taskCompleted: return 0
        case .taskCreated: return 1
        case .noteUpdated: return 2
        }
    }

    // MARK: - Type-aware helpers

    /// Whole calendar days from `now` to `date` (negative when `date` is in the past).
    /// Used for anchor countdowns (days to PO / days to decision).
    public static func daysRemaining(to date: Date, from now: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    /// Which base task-derived KPI tiles to show for a project type. Type-specific
    /// extras (deal value, days-to-anchor) are appended by the view from project data.
    public static func kpiLabels(for type: ProjectType) -> [String] {
        switch type {
        case .sales: return ["Open", "Done"]
        case .implementation, .audit, .internalDev, .generic:
            return ["Open", "Done", "Overdue"]
        }
    }

    // MARK: - Key-date diff

    /// Value-type snapshot of one editor key-date row. Equatable over all four
    /// fields so the diff can detect any change without per-field comparisons.
    public struct KeyDateDraft: Equatable, Sendable {
        public let anchorKey: String
        public let label: String
        public let date: Date
        public let isContractual: Bool

        public init(anchorKey: String, label: String, date: Date, isContractual: Bool) {
            self.anchorKey = anchorKey
            self.label = label
            self.date = date
            self.isContractual = isContractual
        }
    }

    /// Diffs the editor's desired key dates against the currently-persisted set.
    ///
    /// - Parameters:
    ///   - current: Drafts built from the persisted `ProjectKeyDate` rows.
    ///   - desired: Drafts currently held in the editor's `@State`.
    /// - Returns:
    ///   - `upserts`: Drafts that are new (anchorKey absent in `current`) or whose
    ///     label/date/isContractual changed. No-op entries (identical) are omitted.
    ///   - `deletions`: Anchor keys present in `current` but absent from `desired`.
    public static func keyDateDiff(
        current: [KeyDateDraft],
        desired: [KeyDateDraft]
    ) -> (upserts: [KeyDateDraft], deletions: [String]) {
        let currentByKey = Dictionary(uniqueKeysWithValues: current.map { ($0.anchorKey, $0) })
        let desiredByKey = Dictionary(uniqueKeysWithValues: desired.map { ($0.anchorKey, $0) })

        let upserts = desired.filter { draft in
            currentByKey[draft.anchorKey] != draft
        }
        let deletions = current.compactMap { existing in
            desiredByKey[existing.anchorKey] == nil ? existing.anchorKey : nil
        }
        return (upserts: upserts, deletions: deletions)
    }

    // MARK: - Shared predicates

    /// Defensive soft-delete filter; callers are expected to pass live rows.
    private static func live(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.deletedAt == nil }
    }

    /// Overdue = soft due date strictly behind `now`.
    private static func isOverdue(_ task: TaskItem, now: Date) -> Bool {
        guard let dueAt = task.dueAt else { return false }
        return dueAt < now
    }

    private enum DeadlineUrgency {
        case none
        case withinWindow
        case passed
    }

    /// Buckets a hard deadline relative to `now`: strictly behind = `.passed`;
    /// `now ... now + deadlineWarningWindow` (inclusive) = `.withinWindow`.
    private static func deadlineUrgency(_ task: TaskItem, now: Date) -> DeadlineUrgency {
        guard let deadlineAt = task.deadlineAt else { return .none }
        if deadlineAt < now { return .passed }
        if deadlineAt <= now.addingTimeInterval(deadlineWarningWindow) { return .withinWindow }
        return .none
    }
}
