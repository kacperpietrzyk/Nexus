import Foundation
import NexusCore
import SwiftData

// MARK: - Pure selectors + grouping helpers (all unit-tested, no private store access)

extension LiquidTodayModel {

    // MARK: - Project selectors

    /// Pinned-first (pinnedAt desc, nil last), then by updatedAt desc; capped.
    /// Internal so the ordering contract is unit-testable.
    static func selectTodayProjects(_ all: [Project], cap: Int = 5) -> [Project] {
        let pinned = all.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
        let rest = all.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
        return Array((pinned + rest).prefix(cap))
    }

    /// Real progress = done/total over each active project's non-deleted tasks
    /// (single fetch, grouped in memory — same data `ProjectPageView` reads).
    /// Internal so the ordering contract is unit-testable.
    static func projectProgress(
        activeProjects: [Project],
        modelContext: ModelContext
    ) throws -> [LiquidProjectProgress] {
        guard !activeProjects.isEmpty else { return [] }
        let tasks = try modelContext.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt == nil && $0.projectID != nil && $0.isTemplate == false })
        )
        let byProject = Dictionary(grouping: tasks, by: { $0.projectID })
        return
            activeProjects
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { project in
                let projectTasks = byProject[project.id] ?? []
                return LiquidProjectProgress(
                    project: project,
                    doneCount: projectTasks.count(where: { $0.status == .done }),
                    totalCount: projectTasks.count
                )
            }
    }

    // MARK: - Up Next

    /// Returns today's not-yet-ended, non-all-day calendar events sorted by start
    /// ascending and capped to `cap`. An event is "not yet ended" when its `end`
    /// is strictly after `now` and it falls on the same calendar day as `now`.
    /// All-day events are excluded to match the inspector's original Up Next intent.
    static func upNextEvents(_ events: [CalendarEvent], now: Date, cap: Int = 3) -> [CalendarEvent] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        return
            events
            .filter { !$0.isAllDay && $0.end > now && $0.start >= dayStart && $0.start < dayEnd }
            .sorted { $0.start < $1.start }
            .prefix(cap)
            .map { $0 }
    }

    /// Total count of today's not-yet-ended, non-all-day events (uncapped).
    /// The view uses this to render "+N more → Calendar" when the count exceeds `cap`.
    static func upNextEventCount(_ events: [CalendarEvent], now: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return events.filter { !$0.isAllDay && $0.end > now && $0.start >= dayStart && $0.start < dayEnd }.count
    }

    // MARK: - Agenda + priority grouping

    /// Builds the agenda rows: timed calendar events + accepted blocks sorted
    /// by start; all-day events float to the top of the list.
    static func agendaItems(events: [CalendarEvent], blocks: [ScheduledBlock]) -> [LiquidAgendaItem] {
        let eventItems = events.map { event in
            LiquidAgendaItem(
                id: "event:\(event.id)",
                title: event.title,
                subtitle: event.location,
                start: event.start,
                end: event.end,
                isAllDay: event.isAllDay,
                kind: .meeting
            )
        }
        let blockItems = blocks.map { block in
            LiquidAgendaItem(
                id: "block:\(block.id.uuidString)",
                title: block.title,
                subtitle: "Focus block",
                start: block.start,
                end: block.end,
                isAllDay: false,
                kind: .focus
            )
        }
        return (eventItems + blockItems).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id < rhs.id
        }
    }

    /// Returns a ranked shortlist (≤ `cap`) of tasks for the Top Priorities card,
    /// sorted by: pinned first → overdue before not → priority high→low →
    /// due date soonest first (nil last) → original index (stable tiebreak).
    /// `now` should be the start of today so `isOverdue` = `dueAt < now`.
    static func rankedTodayPriorities(
        _ tasks: [TaskItem],
        now: Date = .now,
        cap: Int = 5
    ) -> [TaskItem] {
        struct Keyed {
            let index: Int
            let task: TaskItem
            let isOverdue: Bool
        }
        let keyed = tasks.enumerated().map { index, task in
            Keyed(
                index: index,
                task: task,
                isOverdue: task.dueAt.map { $0 < now } ?? false
            )
        }
        let sorted = keyed.sorted { lhs, rhs in
            // 1. Pinned first
            let lhsPinned = lhs.task.pinnedAsFocus ? 0 : 1
            let rhsPinned = rhs.task.pinnedAsFocus ? 0 : 1
            if lhsPinned != rhsPinned { return lhsPinned < rhsPinned }
            // 2. Overdue before not
            let lhsOverdue = lhs.isOverdue ? 0 : 1
            let rhsOverdue = rhs.isOverdue ? 0 : 1
            if lhsOverdue != rhsOverdue { return lhsOverdue < rhsOverdue }
            // 3. Priority high → low (higher rawValue = higher priority)
            if lhs.task.priority.rawValue != rhs.task.priority.rawValue {
                return lhs.task.priority.rawValue > rhs.task.priority.rawValue
            }
            // 4. Due date soonest first; nil last
            let lhsDue = lhs.task.dueAt ?? .distantFuture
            let rhsDue = rhs.task.dueAt ?? .distantFuture
            if lhsDue != rhsDue { return lhsDue < rhsDue }
            // 5. Original index (stable tiebreak)
            return lhs.index < rhs.index
        }
        return Array(sorted.prefix(cap).map(\.task))
    }

    /// Groups overdue + today tasks (deduped by id, overdue first) into
    /// High/Medium/Low/None priority sections, descending priority — the
    /// spec §Top Priorities grouping over the existing `TodayQuery` buckets.
    static func priorityGroups(overdue: [TaskItem], today: [TaskItem]) -> [LiquidPriorityGroup] {
        var seen: Set<UUID> = []
        var combined: [TaskItem] = []
        for task in overdue + today where !seen.contains(task.id) {
            seen.insert(task.id)
            combined.append(task)
        }
        let byPriority = Dictionary(grouping: combined, by: \.priority)
        let order: [TaskPriority] = [.high, .medium, .low, .none]
        return order.compactMap { priority in
            guard let tasks = byPriority[priority], !tasks.isEmpty else { return nil }
            return LiquidPriorityGroup(priority: priority, tasks: tasks)
        }
    }
}
