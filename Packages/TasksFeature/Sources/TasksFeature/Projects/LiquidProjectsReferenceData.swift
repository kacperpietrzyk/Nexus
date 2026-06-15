import Foundation
import NexusCore

@MainActor
enum LiquidProjectsReferenceData {
    struct Snapshot {
        let project: Project
        let tasks: [TaskItem]
        let sections: [Section]
        let sectionNamesByID: [UUID: String]
        let milestones: [ProjectExecutionModel.Milestone]
        let progress: Double
        let health: ProjectExecutionModel.ProjectHealth
        let risks: [ProjectExecutionModel.ProjectRisk]
        let activity: [ProjectExecutionModel.ActivityEntry]
        let descriptionLine: String
        let commentCountsByTask: [UUID: Int]
        let subtaskCountsByTask: [UUID: Int]
    }

    // swiftlint:disable:next function_body_length
    static func snapshot(now: Date) -> Snapshot {
        let project = Project(name: "Product Roadmap", color: "spark", status: .active)
        project.createdAt = now.addingTimeInterval(-42 * 86_400)
        project.updatedAt = now.addingTimeInterval(-35 * 60)

        let sections: [Section] = [
            Section(projectID: project.id, name: "Discovery & Research", orderIndex: 0),
            Section(projectID: project.id, name: "MVP Foundation", orderIndex: 1),
            Section(projectID: project.id, name: "Core Platform", orderIndex: 2),
            Section(projectID: project.id, name: "AI Integrations", orderIndex: 3),
            Section(projectID: project.id, name: "Scale & Optimize", orderIndex: 4),
        ]
        let sectionNamesByID = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0.name) })

        func task(
            _ title: String,
            section: Section,
            state: WorkflowState?,
            priority: TaskPriority,
            dueOffsetDays: Int,
            status: TaskStatus = .open
        ) -> TaskItem {
            let item = TaskItem(
                title: title,
                dueAt: now.addingTimeInterval(TimeInterval(dueOffsetDays) * 86_400),
                priority: priority,
                status: status,
                projectID: project.id,
                sectionID: section.id,
                workflowState: state
            )
            item.createdAt = now.addingTimeInterval(TimeInterval(-10 + dueOffsetDays) * 86_400)
            item.updatedAt = now.addingTimeInterval(TimeInterval(-dueOffsetDays) * 3_600)
            if status == .done {
                item.lastCompletedAt = now.addingTimeInterval(TimeInterval(dueOffsetDays) * 3_600)
            }
            return item
        }

        var tasks: [TaskItem] = []
        tasks.append(task("Mobile onboarding flow", section: sections[2], state: .todo, priority: .high, dueOffsetDays: 6))
        tasks.append(task("Team permissions UI", section: sections[2], state: .todo, priority: .medium, dueOffsetDays: 8))
        tasks.append(task("Import from Linear", section: sections[2], state: .todo, priority: .low, dueOffsetDays: 9))
        tasks.append(task("AI Daily Brief v2", section: sections[3], state: .inProgress, priority: .high, dueOffsetDays: 2))
        tasks.append(task("Smart search improvements", section: sections[3], state: .inProgress, priority: .medium, dueOffsetDays: 4))
        tasks.append(task("Project templates", section: sections[1], state: .inProgress, priority: .medium, dueOffsetDays: 5))
        tasks.append(task("Calendar integrations", section: sections[3], state: .inReview, priority: .medium, dueOffsetDays: 1))
        tasks.append(task("Focus timer enhancements", section: sections[4], state: .inReview, priority: .low, dueOffsetDays: 3))
        tasks.append(task("Notifications center", section: sections[4], state: .inReview, priority: .low, dueOffsetDays: 7))
        tasks.append(task("Task dependencies", section: sections[1], state: .done, priority: .low, dueOffsetDays: -3, status: .done))
        tasks.append(task("Quick capture", section: sections[0], state: .done, priority: .low, dueOffsetDays: -5, status: .done))
        tasks.append(task("AI suggestions v1", section: sections[0], state: .done, priority: .medium, dueOffsetDays: -7, status: .done))
        for index in [1, 4, 5, 8] {
            tasks[index].statusRaw = TaskStatus.done.rawValue
            tasks[index].workflowStateRaw = WorkflowState.done.rawValue
            tasks[index].lastCompletedAt = now.addingTimeInterval(TimeInterval(-index) * 3_600)
        }
        tasks[3].deadlineAt = now.addingTimeInterval(2 * 86_400)
        tasks[6].deadlineAt = now.addingTimeInterval(24 * 3_600)

        let tasksBySection = Dictionary(grouping: tasks, by: { $0.sectionID ?? UUID() })
        let notes = [
            Note(title: "Sprint review notes", plainText: "Jamie Park moved PRD-233 to In Progress."),
            Note(title: "Roadmap risk register", plainText: "Calendar integrations need attention."),
        ]
        notes[0].updatedAt = now.addingTimeInterval(-40 * 60)
        notes[1].updatedAt = now.addingTimeInterval(-3 * 3_600)

        return Snapshot(
            project: project,
            tasks: tasks,
            sections: sections,
            sectionNamesByID: sectionNamesByID,
            milestones: ProjectExecutionModel.milestones(sections: sections, tasksBySection: tasksBySection),
            progress: ProjectExecutionModel.progress(tasks: tasks),
            health: ProjectExecutionModel.health(tasks: tasks, now: now),
            risks: ProjectExecutionModel.risks(tasks: tasks, now: now),
            activity: ProjectExecutionModel.activity(tasks: tasks, notes: notes),
            descriptionLine: "Build the next generation of AI-native productivity.",
            commentCountsByTask: [tasks[3].id: 8, tasks[6].id: 5, tasks[4].id: 5, tasks[5].id: 3],
            subtaskCountsByTask: [tasks[0].id: 5, tasks[3].id: 8, tasks[6].id: 5]
        )
    }
}
