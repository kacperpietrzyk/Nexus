import Foundation
import NexusCore

public enum RoadmapModel {
    public struct ProjectBar: Identifiable, Equatable, Sendable {
        public let projectID: UUID
        public let name: String
        public let glyphToken: String
        public let start: Date
        public let end: Date?
        public let health: ProjectExecutionModel.ProjectHealth
        public let progress: Double
        public let milestones: [MilestoneMarker]

        public var id: UUID { projectID }

        public init(
            projectID: UUID,
            name: String,
            glyphToken: String,
            start: Date,
            end: Date?,
            health: ProjectExecutionModel.ProjectHealth,
            progress: Double,
            milestones: [MilestoneMarker]
        ) {
            self.projectID = projectID
            self.name = name
            self.glyphToken = glyphToken
            self.start = start
            self.end = end
            self.health = health
            self.progress = progress
            self.milestones = milestones
        }
    }

    public struct MilestoneMarker: Identifiable, Equatable, Sendable {
        public let sectionID: UUID
        public let title: String
        public let date: Date
        public let state: ProjectExecutionModel.MilestoneState

        public var id: UUID { sectionID }

        public init(
            sectionID: UUID,
            title: String,
            date: Date,
            state: ProjectExecutionModel.MilestoneState
        ) {
            self.sectionID = sectionID
            self.title = title
            self.date = date
            self.state = state
        }
    }

    public struct CycleBar: Identifiable, Equatable, Sendable {
        public let cycleID: UUID
        public let name: String
        public let startAt: Date
        public let endAt: Date
        public let status: CycleStatus

        public var id: UUID { cycleID }

        public init(cycleID: UUID, name: String, startAt: Date, endAt: Date, status: CycleStatus) {
            self.cycleID = cycleID
            self.name = name
            self.startAt = startAt
            self.endAt = endAt
            self.status = status
        }
    }

    public static func bar(project: Project, tasks: [TaskItem], sections: [Section], now: Date) -> ProjectBar {
        let liveTasks = live(tasks, projectID: project.id)
        let liveSections = live(sections, projectID: project.id)
        let start = spanStart(project: project, tasks: liveTasks)
        let end = spanEnd(tasks: liveTasks, start: start)
        let tasksBySection = tasksByLiveSection(liveTasks)
        let markerDates = milestoneDates(tasksBySection: tasksBySection)
        let milestones = ProjectExecutionModel.milestones(sections: liveSections, tasksBySection: tasksBySection)
            .compactMap { milestone -> MilestoneMarker? in
                guard let date = markerDates[milestone.id] else { return nil }
                return MilestoneMarker(
                    sectionID: milestone.id,
                    title: milestone.title,
                    date: date,
                    state: milestone.state
                )
            }

        return ProjectBar(
            projectID: project.id,
            name: project.name,
            glyphToken: project.color,
            start: start,
            end: end,
            health: ProjectExecutionModel.health(tasks: liveTasks, now: now),
            progress: ProjectExecutionModel.progress(tasks: liveTasks),
            milestones: milestones
        )
    }

    public static func cycleBars(_ cycles: [Cycle]) -> [CycleBar] {
        cycles
            .filter { $0.deletedAt == nil }
            .map {
                CycleBar(
                    cycleID: $0.id,
                    name: $0.name,
                    startAt: $0.startAt,
                    endAt: $0.endAt,
                    status: $0.status
                )
            }
            .sorted {
                if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
                return $0.cycleID.uuidString < $1.cycleID.uuidString
            }
    }

    private static func live(_ tasks: [TaskItem], projectID: UUID) -> [TaskItem] {
        tasks.filter { $0.projectID == projectID && $0.deletedAt == nil && !$0.isTemplate }
    }

    private static func live(_ sections: [Section], projectID: UUID) -> [Section] {
        sections.filter { $0.projectID == projectID && $0.deletedAt == nil }
    }

    private static func spanStart(project: Project, tasks: [TaskItem]) -> Date {
        var candidates = [project.createdAt]
        candidates.append(contentsOf: tasks.compactMap(\.startAt))
        candidates.append(contentsOf: tasks.compactMap(\.dueAt))
        return candidates.min() ?? project.createdAt
    }

    private static func spanEnd(tasks: [TaskItem], start: Date) -> Date? {
        var candidates = tasks.compactMap(\.dueAt)
        candidates.append(contentsOf: tasks.compactMap(\.deadlineAt))
        guard let end = candidates.max() else { return nil }
        return max(end, start)
    }

    private static func tasksByLiveSection(_ tasks: [TaskItem]) -> [UUID: [TaskItem]] {
        Dictionary(
            grouping: tasks.compactMap { task -> (UUID, TaskItem)? in
                guard let sectionID = task.sectionID else { return nil }
                return (sectionID, task)
            }
        ) { $0.0 }
        .mapValues { $0.map(\.1) }
    }

    private static func milestoneDates(tasksBySection: [UUID: [TaskItem]]) -> [UUID: Date] {
        tasksBySection.compactMapValues { tasks in
            tasks.compactMap(markerDate(for:)).max()
        }
    }

    private static func markerDate(for task: TaskItem) -> Date? {
        if let deadlineAt = task.deadlineAt { return deadlineAt }
        if let dueAt = task.dueAt { return dueAt }
        if task.status == .done { return task.lastCompletedAt }
        return nil
    }
}
