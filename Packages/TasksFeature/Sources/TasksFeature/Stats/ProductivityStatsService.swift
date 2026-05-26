import Foundation
import NexusCore
import SwiftData

/// Aggregates task-completion data for the productivity dashboard.
///
/// Counts use `TaskItem.lastCompletedAt`, so a recurring task contributes one
/// bucket entry regardless of how many times it has been completed. Full
/// per-completion accounting requires a future `CompletionRecord` entity.
@MainActor
public final class ProductivityStatsService {
    private let context: ModelContext
    /// Calendar used to derive day buckets and streak windows. Exposed so
    /// dashboard views (and tests) can stay aligned with the same calendar
    /// the service uses internally.
    public let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    public struct DailyCount: Identifiable, Sendable {
        public var id: Date { day }

        public let day: Date
        public let count: Int
    }

    public struct PerProject: Identifiable, Sendable {
        public let id: UUID
        public let projectName: String
        public let completedCount: Int
    }

    public func completedPerDay(last days: Int = 30, now: Date = .now) throws -> [DailyCount] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let tasks = try completedTasks()

        let completions = tasks.compactMap(\.lastCompletedAt).filter { completion in
            completion >= start && completion < end
        }
        let bucket = Dictionary(grouping: completions, by: calendar.startOfDay(for:))
            .mapValues(\.count)

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyCount(day: day, count: bucket[day] ?? 0)
        }
    }

    public func currentStreakDays(now: Date = .now) throws -> Int {
        let counts = try completedPerDay(last: 365, now: now).reversed()
        var streak = 0

        for count in counts {
            guard count.count >= 1 else { break }
            streak += 1
        }

        return streak
    }

    // TODO: track recurring completion history (see ProductivityStatsService notes)
    public func completedPerProject(since: Date) throws -> [PerProject] {
        let tasks = try completedTasks().filter { task in
            guard let completedAt = task.lastCompletedAt else { return false }
            return completedAt >= since
        }

        let grouped = Dictionary(grouping: tasks.compactMap(\.projectID), by: { $0 })
            .mapValues(\.count)
        let projectRepository = ProjectRepository(context: context)

        return try grouped.compactMap { projectID, count in
            guard
                let project = try projectRepository.find(id: projectID),
                project.deletedAt == nil,
                project.archivedAt == nil
            else {
                return nil
            }

            return PerProject(id: projectID, projectName: project.name, completedCount: count)
        }
        .sorted {
            if $0.completedCount == $1.completedCount {
                return $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending
            }
            return $0.completedCount > $1.completedCount
        }
    }

    private func completedTasks() throws -> [TaskItem] {
        let doneStatus = TaskStatus.done.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil && task.statusRaw == doneStatus
            }
        )
        return try context.fetch(descriptor).filter { $0.lastCompletedAt != nil }
    }
}
