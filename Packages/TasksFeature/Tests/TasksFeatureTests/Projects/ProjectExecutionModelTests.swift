import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("ProjectExecutionModel pure helpers")
struct ProjectExecutionModelTests {

    // MARK: - Fixtures

    /// All fixtures pivot around a fixed instant — never `Date.now`.
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func hours(_ value: Double) -> TimeInterval { value * 3_600 }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, ProjectSection.self, Note.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func makeTask(
        _ context: ModelContext,
        title: String,
        status: TaskStatus = .open,
        workflowState: WorkflowState? = nil,
        dueAt: Date? = nil,
        deadlineAt: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        lastCompletedAt: Date? = nil,
        deletedAt: Date? = nil,
        sectionID: UUID? = nil
    ) -> TaskItem {
        let task = TaskItem(
            title: title,
            dueAt: dueAt,
            deadlineAt: deadlineAt,
            status: status,
            sectionID: sectionID,
            workflowState: workflowState
        )
        task.createdAt = createdAt
        task.updatedAt = updatedAt
        task.lastCompletedAt = lastCompletedAt
        task.deletedAt = deletedAt
        context.insert(task)
        return task
    }

    // MARK: - Milestones

    @Test("Milestones follow section orderIndex, not input order")
    @MainActor
    func milestonesOrdering() throws {
        let context = try makeContext()
        let projectID = UUID()
        let second = ProjectSection(projectID: projectID, name: "Second", orderIndex: 2)
        let first = ProjectSection(projectID: projectID, name: "First", orderIndex: 1)
        context.insert(second)
        context.insert(first)

        let milestones = ProjectExecutionModel.milestones(
            sections: [second, first],
            tasksBySection: [:]
        )

        #expect(milestones.map(\.title) == ["First", "Second"])
        #expect(milestones.map(\.id) == [first.id, second.id])
    }

    @Test("Milestone states: all done = completed, some done = in progress, none done = upcoming")
    @MainActor
    func milestoneStates() throws {
        let context = try makeContext()
        let projectID = UUID()
        let doneSection = ProjectSection(projectID: projectID, name: "Done", orderIndex: 0)
        let mixedSection = ProjectSection(projectID: projectID, name: "Mixed", orderIndex: 1)
        let freshSection = ProjectSection(projectID: projectID, name: "Fresh", orderIndex: 2)
        for section in [doneSection, mixedSection, freshSection] { context.insert(section) }

        let tasksBySection: [UUID: [TaskItem]] = [
            doneSection.id: [
                makeTask(context, title: "d1", status: .done),
                makeTask(context, title: "d2", status: .done),
            ],
            mixedSection.id: [
                makeTask(context, title: "m1", status: .done),
                makeTask(context, title: "m2"),
            ],
            freshSection.id: [
                makeTask(context, title: "f1"),
                makeTask(context, title: "f2"),
            ],
        ]

        let milestones = ProjectExecutionModel.milestones(
            sections: [doneSection, mixedSection, freshSection],
            tasksBySection: tasksBySection
        )

        #expect(milestones.map(\.state) == [.completed, .inProgress, .upcoming])
    }

    @Test("In-flight workflow state (inProgress/inReview) marks an otherwise-undone milestone in progress")
    @MainActor
    func milestoneInFlightWorkflow() throws {
        let context = try makeContext()
        let projectID = UUID()
        let active = ProjectSection(projectID: projectID, name: "Active", orderIndex: 0)
        let queued = ProjectSection(projectID: projectID, name: "Queued", orderIndex: 1)
        context.insert(active)
        context.insert(queued)

        let tasksBySection: [UUID: [TaskItem]] = [
            active.id: [makeTask(context, title: "a1", workflowState: .inReview)],
            // backlog/todo are queued, not in-flight — still upcoming.
            queued.id: [makeTask(context, title: "q1", workflowState: .todo)],
        ]

        let milestones = ProjectExecutionModel.milestones(
            sections: [active, queued],
            tasksBySection: tasksBySection
        )

        #expect(milestones.map(\.state) == [.inProgress, .upcoming])
    }

    @Test("Empty section and deleted-only section are upcoming")
    @MainActor
    func milestoneEmptyAndDeleted() throws {
        let context = try makeContext()
        let projectID = UUID()
        let empty = ProjectSection(projectID: projectID, name: "Empty", orderIndex: 0)
        let ghost = ProjectSection(projectID: projectID, name: "Ghost", orderIndex: 1)
        context.insert(empty)
        context.insert(ghost)

        let tasksBySection: [UUID: [TaskItem]] = [
            ghost.id: [makeTask(context, title: "gone", status: .done, deletedAt: Self.now)]
        ]

        let milestones = ProjectExecutionModel.milestones(
            sections: [empty, ghost],
            tasksBySection: tasksBySection
        )

        #expect(milestones.map(\.state) == [.upcoming, .upcoming])
    }

    // MARK: - Progress

    @Test("Progress is done/total; empty input is 0")
    @MainActor
    func progressBasics() throws {
        let context = try makeContext()
        #expect(ProjectExecutionModel.progress(tasks: []) == 0)

        let tasks = [
            makeTask(context, title: "a", status: .done),
            makeTask(context, title: "b"),
            makeTask(context, title: "c"),
        ]
        #expect(ProjectExecutionModel.progress(tasks: tasks) == 1.0 / 3.0)

        let allDone = [
            makeTask(context, title: "x", status: .done),
            makeTask(context, title: "y", status: .done),
        ]
        #expect(ProjectExecutionModel.progress(tasks: allDone) == 1)
    }

    @Test("Progress ignores deleted tasks")
    @MainActor
    func progressIgnoresDeleted() throws {
        let context = try makeContext()
        let tasks = [
            makeTask(context, title: "live done", status: .done),
            makeTask(context, title: "live open"),
            makeTask(context, title: "deleted done", status: .done, deletedAt: Self.now),
        ]
        #expect(ProjectExecutionModel.progress(tasks: tasks) == 0.5)
    }

    // MARK: - Health

    @Test("Empty and all-done projects are on track")
    @MainActor
    func healthEmptyAndAllDone() throws {
        let context = try makeContext()
        #expect(ProjectExecutionModel.health(tasks: [], now: Self.now) == .onTrack)

        let done = [makeTask(context, title: "d", status: .done, dueAt: Self.now.addingTimeInterval(-Self.hours(100)))]
        #expect(ProjectExecutionModel.health(tasks: done, now: Self.now) == .onTrack)
    }

    @Test("Overdue ratio boundaries: exactly 10% on track, above 10% at risk, exactly 30% at risk, above 30% off track")
    @MainActor
    func healthOverdueRatioBoundaries() throws {
        let context = try makeContext()
        let overdueDate = Self.now.addingTimeInterval(-Self.hours(1))

        func openTasks(total: Int, overdue: Int) -> [TaskItem] {
            (0..<total).map { index in
                makeTask(
                    context,
                    title: "t\(index)",
                    dueAt: index < overdue ? overdueDate : nil
                )
            }
        }

        // Thresholds are strict (>), so the exact ratio does NOT escalate.
        #expect(ProjectExecutionModel.health(tasks: openTasks(total: 10, overdue: 1), now: Self.now) == .onTrack)
        #expect(ProjectExecutionModel.health(tasks: openTasks(total: 10, overdue: 2), now: Self.now) == .atRisk)
        #expect(ProjectExecutionModel.health(tasks: openTasks(total: 10, overdue: 3), now: Self.now) == .atRisk)
        #expect(ProjectExecutionModel.health(tasks: openTasks(total: 10, overdue: 4), now: Self.now) == .offTrack)
    }

    @Test("Deadline semantics: passed = off track, within 48h inclusive = at risk, beyond = on track")
    @MainActor
    func healthDeadlines() throws {
        let context = try makeContext()

        let passed = [makeTask(context, title: "p", deadlineAt: Self.now.addingTimeInterval(-1))]
        #expect(ProjectExecutionModel.health(tasks: passed, now: Self.now) == .offTrack)

        let boundary = [makeTask(context, title: "b", deadlineAt: Self.now.addingTimeInterval(Self.hours(48)))]
        #expect(ProjectExecutionModel.health(tasks: boundary, now: Self.now) == .atRisk)

        let far = [makeTask(context, title: "f", deadlineAt: Self.now.addingTimeInterval(Self.hours(48) + 1))]
        #expect(ProjectExecutionModel.health(tasks: far, now: Self.now) == .onTrack)

        // Deadlines on done tasks never count.
        let doneDeadline = [makeTask(context, title: "d", status: .done, deadlineAt: Self.now.addingTimeInterval(-Self.hours(5)))]
        #expect(ProjectExecutionModel.health(tasks: doneDeadline, now: Self.now) == .onTrack)
    }

    // MARK: - Risks

    @Test("Risks pick up overdue and deadline tasks; deadline kind wins when both apply")
    @MainActor
    func risksKinds() throws {
        let context = try makeContext()
        let overdueOnly = makeTask(context, title: "overdue", dueAt: Self.now.addingTimeInterval(-Self.hours(2)))
        let deadlineSoon = makeTask(context, title: "deadline", deadlineAt: Self.now.addingTimeInterval(Self.hours(24)))
        let both = makeTask(
            context,
            title: "both",
            dueAt: Self.now.addingTimeInterval(-Self.hours(50)),
            deadlineAt: Self.now.addingTimeInterval(-Self.hours(1))
        )
        let safe = makeTask(context, title: "safe", dueAt: Self.now.addingTimeInterval(Self.hours(2)))
        let doneOverdue = makeTask(context, title: "done", status: .done, dueAt: Self.now.addingTimeInterval(-Self.hours(2)))

        let risks = ProjectExecutionModel.risks(
            tasks: [overdueOnly, deadlineSoon, both, safe, doneOverdue],
            now: Self.now
        )

        // Most urgent first by anchor date: overdue (-2h), passed deadline (-1h
        // — "both" anchors on its deadline, not its much older dueAt, because
        // the deadline kind wins), then the 24h-out deadline.
        #expect(risks.map(\.taskID) == [overdueOnly.id, both.id, deadlineSoon.id])
        #expect(risks.map(\.kind) == [.overdue, .deadline, .deadline])
        #expect(risks[0].dueAt == overdueOnly.dueAt)
        #expect(risks[1].deadlineAt == both.deadlineAt)
    }

    @Test("Risks are sorted by urgency anchor ascending and capped at limit")
    @MainActor
    func risksSortingAndCap() throws {
        let context = try makeContext()
        let tasks = (0..<7).map { index in
            makeTask(
                context,
                title: "r\(index)",
                dueAt: Self.now.addingTimeInterval(-Self.hours(Double(index + 1)))
            )
        }

        let capped = ProjectExecutionModel.risks(tasks: tasks, now: Self.now, limit: 3)
        // Oldest overdue = most urgent.
        #expect(capped.map(\.title) == ["r6", "r5", "r4"])
        #expect(ProjectExecutionModel.risks(tasks: tasks, now: Self.now).count == 5)
    }

    // MARK: - Activity

    @Test("Activity merges completions, creations, and note updates, newest first, capped")
    @MainActor
    func activityMergeAndCap() throws {
        let context = try makeContext()
        let base = Date(timeIntervalSince1970: 0)
        let completed = makeTask(
            context,
            title: "shipped",
            status: .done,
            createdAt: base,
            updatedAt: Date(timeIntervalSince1970: 50),
            lastCompletedAt: Date(timeIntervalSince1970: 400)
        )
        let created = makeTask(
            context,
            title: "fresh",
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let note = Note(title: "Spec", plainText: "spec")
        note.updatedAt = Date(timeIntervalSince1970: 200)
        note.createdAt = base
        context.insert(note)

        let entries = ProjectExecutionModel.activity(
            tasks: [completed, created],
            notes: [note]
        )

        // "shipped" appears twice: completed at 400 and created at 0.
        #expect(entries.map(\.kind) == [.taskCompleted, .taskCreated, .noteUpdated, .taskCreated])
        #expect(entries.map(\.title) == ["shipped", "fresh", "Spec", "shipped"])
        #expect(entries.map(\.timestamp.timeIntervalSince1970) == [400, 300, 200, 0])

        let capped = ProjectExecutionModel.activity(tasks: [completed, created], notes: [note], limit: 2)
        #expect(capped.map(\.title) == ["shipped", "fresh"])
    }

    @Test("Completion timestamp falls back to updatedAt; terminal non-completions are not 'completed'")
    @MainActor
    func activityCompletionSemantics() throws {
        let context = try makeContext()
        let noStamp = makeTask(
            context,
            title: "quiet done",
            status: .done,
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        // Production reconcile forces status == .done on a canceled workflow
        // (WorkflowState.forcedStatus); mirror that here so the
        // isTerminalNonCompletion guard is actually exercised — without .done
        // the status check would short-circuit first.
        let canceled = makeTask(
            context,
            title: "canceled",
            status: .done,
            workflowState: .canceled,
            createdAt: Date(timeIntervalSince1970: 600),
            updatedAt: Date(timeIntervalSince1970: 800)
        )

        let entries = ProjectExecutionModel.activity(tasks: [noStamp, canceled], notes: [])

        // canceled/duplicate force status == .done but are not completed work
        // (WorkflowState.isTerminalNonCompletion) — only its creation shows up.
        #expect(entries.map(\.kind) == [.taskCompleted, .taskCreated, .taskCreated])
        #expect(entries.map(\.title) == ["quiet done", "canceled", "quiet done"])
        #expect(entries[0].timestamp == Date(timeIntervalSince1970: 700))
    }

    @Test("Activity entry ids are unique even when one task yields two entries")
    @MainActor
    func activityIDUniqueness() throws {
        let context = try makeContext()
        let task = makeTask(
            context,
            title: "twice",
            status: .done,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            lastCompletedAt: Date(timeIntervalSince1970: 200)
        )

        let entries = ProjectExecutionModel.activity(tasks: [task], notes: [])
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.id)).count == 2)
    }
}
