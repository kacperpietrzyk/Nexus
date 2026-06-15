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

    /// Snapshot of goal attainment for the dashboard (T5).
    public struct GoalProgress: Equatable, Sendable {
        public let dailyCompleted: Int
        public let weeklyCompleted: Int
        public let dailyTarget: Int
        public let weeklyTarget: Int
        /// Streak (in days, ending yesterday) that breaks if nothing gets
        /// completed today. nil when today already has a completion or no
        /// streak exists.
        public let streakAtRisk: Int?

        public init(
            dailyCompleted: Int,
            weeklyCompleted: Int,
            dailyTarget: Int,
            weeklyTarget: Int,
            streakAtRisk: Int?
        ) {
            self.dailyCompleted = dailyCompleted
            self.weeklyCompleted = weeklyCompleted
            self.dailyTarget = dailyTarget
            self.weeklyTarget = weeklyTarget
            self.streakAtRisk = streakAtRisk
        }

        /// 0...1, clamped; 0 when the target is disabled (≤ 0).
        public var dailyFraction: Double { Self.fraction(dailyCompleted, of: dailyTarget) }
        /// 0...1, clamped; 0 when the target is disabled (≤ 0).
        public var weeklyFraction: Double { Self.fraction(weeklyCompleted, of: weeklyTarget) }

        private static func fraction(_ completed: Int, of target: Int) -> Double {
            guard target > 0 else { return 0 }
            return min(1, Double(completed) / Double(target))
        }
    }

    /// Derives today's and the current calendar week's completion counts
    /// against the configured targets. The week window is the service
    /// calendar's `weekOfYear` interval, so locale first-weekday rules apply.
    public func goalProgress(preferences: GoalsPreferences, now: Date = .now) throws -> GoalProgress {
        let dailyCompleted = try completedPerDay(last: 1, now: now).first?.count ?? 0

        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let weeklyCompleted = try completedTasks()
            .compactMap(\.lastCompletedAt)
            .filter { completion in week?.contains(completion) ?? false }
            .count

        // Streak protection is part of the DAILY goal: a disabled daily target
        // (0 = off) must stay fully silent, never cross-firing streak-at-risk
        // state past it (e.g. onto a weekly-only Goals card).
        var streakAtRisk: Int?
        let dailyGoalEnabled = preferences.dailyCompletionTarget > 0
        if dailyGoalEnabled, dailyCompleted == 0, let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            let streakEndingYesterday = try currentStreakDays(now: yesterday)
            streakAtRisk = streakEndingYesterday > 0 ? streakEndingYesterday : nil
        }

        return GoalProgress(
            dailyCompleted: dailyCompleted,
            weeklyCompleted: weeklyCompleted,
            dailyTarget: preferences.dailyCompletionTarget,
            weeklyTarget: preferences.weeklyCompletionTarget,
            streakAtRisk: streakAtRisk
        )
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
                task.deletedAt == nil && task.statusRaw == doneStatus && task.isTemplate == false
            }
        )
        return try context.fetch(descriptor).filter { $0.lastCompletedAt != nil }
    }
}
