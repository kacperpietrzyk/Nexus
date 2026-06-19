import Foundation
import NexusCore
import SwiftData

/// A schedulable task for the inspector: open, no due date, and no live
/// `ScheduledBlock` yet — a plain value so the views stay store-free.
struct WeekUnscheduledTask: Identifiable, Equatable {
    let id: UUID
    let title: String
    let projectName: String?
    let estimatedSeconds: Int?
}

/// Loads the Unscheduled Tasks from the REAL store: the same
/// `TodayQuery.noDate()` bucket the Today surfaces use, minus tasks that
/// already have a live `ScheduledBlock` (so a drop visibly moves the task out
/// of the list), with project names resolved for the tag pills.
enum WeekUnscheduledLoader {
    /// Scheduled-block length when placing a task into a free gap: the task's
    /// own estimate (1 h default), floored at one snap step and capped at the
    /// gap — shared by the inspector's Focus CTA and Schedule action.
    static func clampDuration(estimate: Int?, gap: DateInterval) -> TimeInterval {
        let raw = estimate.map(TimeInterval.init) ?? WeekGridMetrics.defaultBlockDuration
        return min(max(raw, TimeInterval(WeekGridMetrics.snapMinutes * 60)), gap.duration)
    }

    @MainActor
    static func load(modelContext: ModelContext) -> [WeekUnscheduledTask] {
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let tasks =
            (try? TodayQuery().noDate(excludingProjectIDs: archivedProjectIDs).apply(in: modelContext)) ?? []

        let blockDescriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let scheduledTaskIDs = Set(((try? modelContext.fetch(blockDescriptor)) ?? []).map(\.taskID))

        let projectDescriptor = FetchDescriptor<Project>()
        let liveProjects = ((try? modelContext.fetch(projectDescriptor)) ?? [])
            .filter { $0.deletedAt == nil && $0.archivedAt == nil }
        let projectNamesByID = Dictionary(
            liveProjects.map { ($0.id, $0.name) },
            uniquingKeysWith: { current, _ in current }
        )

        return
            tasks
            .filter { !scheduledTaskIDs.contains($0.id) }
            .map { task in
                WeekUnscheduledTask(
                    id: task.id,
                    title: task.title,
                    projectName: task.projectID.flatMap { projectNamesByID[$0] },
                    estimatedSeconds: task.estimatedDurationSeconds
                )
            }
    }
}

/// Shared "1h 30m" duration formatting for the week surfaces.
enum WeekDurationText {
    static func text(for duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}
