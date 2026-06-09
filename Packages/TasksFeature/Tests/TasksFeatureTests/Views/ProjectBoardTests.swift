import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("Project board bucketing + workflow/status mutations")
struct ProjectBoardTests {

    // MARK: - Pure bucketing seam

    @Test("Primary lanes always present even when empty")
    func primaryLanesAlwaysPresent() {
        let columns = projectBoardColumns(for: [])
        let states = columns.map(\.state)
        #expect(states == [nil, .backlog, .todo, .inProgress, .inReview, .done])
        #expect(columns.allSatisfy { $0.tasks.isEmpty })
    }

    @Test("Tasks bucket into the column matching their workflowState")
    func tasksBucketByWorkflowState() {
        let projectID = UUID()
        let backlog = TaskItem(title: "B", projectID: projectID, workflowState: .backlog)
        let inProgress = TaskItem(title: "P", projectID: projectID, workflowState: .inProgress)
        let plain = TaskItem(title: "Plain", projectID: projectID)  // workflowState nil

        let columns = projectBoardColumns(for: [backlog, inProgress, plain])
        let byState = Dictionary(uniqueKeysWithValues: columns.map { ($0.state, $0.tasks) })

        #expect(byState[nil]?.map(\.id) == [plain.id])
        #expect(byState[.backlog]?.map(\.id) == [backlog.id])
        #expect(byState[.inProgress]?.map(\.id) == [inProgress.id])
        #expect(byState[.todo]?.isEmpty == true)
    }

    @Test("Terminal closures appear only when non-empty, as trailing lanes")
    func terminalLanesOnlyWhenPresent() {
        let projectID = UUID()
        let canceled = TaskItem(title: "C", projectID: projectID, workflowState: .canceled)

        let withTerminal = projectBoardColumns(for: [canceled])
        #expect(withTerminal.map(\.state).contains(.canceled))
        #expect(withTerminal.last?.state == .canceled)
        // Duplicate has no task → not appended.
        #expect(!withTerminal.map(\.state).contains(.duplicate))

        let withoutTerminal = projectBoardColumns(for: [])
        #expect(!withoutTerminal.map(\.state).contains(.canceled))
        #expect(!withoutTerminal.map(\.state).contains(.duplicate))
    }

    @Test("Column titles render the expected labels")
    func columnTitles() {
        #expect(ProjectBoardColumn.title(for: nil) == "No Status")
        #expect(ProjectBoardColumn.title(for: .inProgress) == "In Progress")
        #expect(ProjectBoardColumn.title(for: .done) == "Done")
        #expect(ProjectBoardColumn.title(for: .canceled) == "Canceled")
    }

    // MARK: - Drag-to-change-status (the real repository write path)

    @Test("Moving a card sets workflowState and reconciles status to open")
    @MainActor
    func moveToInProgressOpens() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 100)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let projectID = UUID()
        let task = TaskItem(title: "Plain project task", projectID: projectID)
        context.insert(task)
        try context.save()
        #expect(task.workflowState == nil)

        try repository.setWorkflowState(.inProgress, on: task)

        #expect(task.workflowState == .inProgress)
        #expect(task.status == .open)
    }

    @Test("Dragging a card into Done completes it (status + lastCompletedAt)")
    @MainActor
    func moveToDoneCompletes() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 200)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let task = TaskItem(title: "T", projectID: UUID(), workflowState: .todo)
        context.insert(task)
        try context.save()

        try repository.setWorkflowState(.done, on: task)

        #expect(task.workflowState == .done)
        #expect(task.status == .done)
        #expect(task.lastCompletedAt == stamp)
    }

    @Test("Dragging into Canceled closes without counting completion")
    @MainActor
    func moveToCanceledClosesWithoutCompletion() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 300)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let task = TaskItem(title: "T", projectID: UUID(), workflowState: .inProgress)
        context.insert(task)
        try context.save()

        try repository.setWorkflowState(.canceled, on: task)

        #expect(task.workflowState == .canceled)
        #expect(task.status == .done)
        #expect(task.lastCompletedAt == nil)  // terminal non-completion (I4)
    }

    // MARK: - Project status lifecycle

    @Test("ProjectRepository.setStatus transitions the lifecycle state")
    @MainActor
    func projectStatusLifecycle() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 400)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Project.self, configurations: config)
        let context = container.mainContext
        let repository = ProjectRepository(context: context, now: { stamp })

        let project = try repository.create(name: "Launch")
        #expect(project.status == .backlog)

        try repository.setStatus(.active, on: project)
        #expect(project.status == .active)
        #expect(project.updatedAt == stamp)

        try repository.setStatus(.completed, on: project)
        #expect(project.status == .completed)
        // archivedAt is orthogonal — setStatus never archives.
        #expect(project.archivedAt == nil)
    }
}
