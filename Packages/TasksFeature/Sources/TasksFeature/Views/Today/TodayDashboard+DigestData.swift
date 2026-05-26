import NexusAgent
import NexusCore
import SwiftData
import SwiftUI

// MARK: - Digest / schedule data helpers

// Static data helpers (digest input, done-today, schedule, calendar) split
// out of `TodayDashboard.swift` purely for `file_length` headroom —
// symmetric with the existing `+EmbeddedToday.swift` / `+Standalone.swift`
// splits. Pure mechanical move: no behaviour, signatures, or call sites
// changed (MP-3.1 slice 1 §11 preemptive sibling extraction).

extension TodayDashboard {
    static let digestTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    struct DigestInput {
        let counts: HeroBriefService.Counts
        let firstTitles: [String]
        let today: [TaskItem]

        func agentBriefRequest(now: Date) -> AgentBriefRequest {
            AgentBriefRequest(
                counts: AgentBriefCounts(
                    overdue: counts.overdue,
                    today: counts.today,
                    noDate: counts.noDate,
                    awaiting: counts.awaiting
                ),
                firstTitles: firstTitles,
                now: now
            )
        }
    }

    @MainActor
    static func digestInput(now: Date, modelContext: ModelContext) throws -> DigestInput {
        let query = TodayQuery()
        let linkRepository = LinkRepository(context: modelContext)
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let overdue = try query.overdue(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let today = try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let doneToday = try Self.doneTodayTasks(now: now, modelContext: modelContext)
        let noDate = try query.noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let awaiting = try query.awaiting(
            now: now,
            modelContext: modelContext,
            linkRepository: linkRepository
        )
        let counts = HeroBriefService.Counts(
            overdue: overdue.count,
            today: today.count,
            noDate: noDate.count,
            awaiting: awaiting.count
        )
        return DigestInput(
            counts: counts,
            firstTitles: Array(today.prefix(3).map(\.title)),
            today: today + doneToday
        )
    }

    /// Tasks that completed today (status == .done, dueAt within today's window). Surfaced so the
    /// day-progress rail can report meaningful done/total + focused-minute counts.
    @MainActor
    static func doneTodayTasks(now: Date, modelContext: ModelContext) throws -> [TaskItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        let doneStatus = TaskStatus.done.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil
                && task.statusRaw == doneStatus
                && task.dueAt != nil
        }
        let descriptor = FetchDescriptor<TaskItem>(predicate: predicate)
        let fetched = try modelContext.fetch(descriptor)
        return fetched.filter { task in
            guard let due = task.dueAt else { return false }
            return due >= startOfDay && due < startOfTomorrow
        }
    }

    @MainActor
    static func scheduleTasks(now: Date, modelContext: ModelContext) throws -> [TaskItem] {
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        return try TodayQuery()
            .today(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
    }

    static func calendarEvents(
        now: Date,
        enabled: Bool,
        provider: any CalendarEventProviding
    ) async -> [CalendarEvent] {
        guard enabled else { return [] }
        return (try? await provider.eventsToday(now: now)) ?? []
    }
}
