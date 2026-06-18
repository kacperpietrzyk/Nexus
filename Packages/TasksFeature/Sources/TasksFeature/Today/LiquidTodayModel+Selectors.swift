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
