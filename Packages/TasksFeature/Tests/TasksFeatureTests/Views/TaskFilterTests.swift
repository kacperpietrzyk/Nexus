import Foundation
import SwiftData
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("TaskFilter v4")
struct TaskFilterTests {
    @Test("Task list accepts segment-driven filters")
    @MainActor
    func taskListAcceptsSegmentFilters() {
        let id = UUID()
        for filter in [
            TaskFilter.all,
            .today,
            .upcoming,
            .inbox,
            .completed,
            .project(id),
            .projectSection(id, UUID()),
            .savedFilter(id),
            .cycle(id),
        ] {
            _ = TaskListView(filter: filter)
        }
    }

    @Test("Cycle filter resolves its title from the cycle lookup with a generic fallback")
    func cycleTitleResolution() {
        let cycleID = UUID()
        #expect(TaskFilter.cycle(cycleID).displayTitle == "Cycle")
        let resolved = TaskFilter.cycle(cycleID).resolvedDisplayTitle(
            cycleName: { id in id == cycleID ? "Sprint 12" : nil }
        )
        #expect(resolved == "Sprint 12")
        // Archive reset never touches cycle selections.
        #expect(TaskFilter.cycle(cycleID).replacingArchivedProject(UUID()) == .cycle(cycleID))
    }

    @Test("Archive reset handles project and section selections")
    func archiveResetHandlesProjectAndSectionSelections() {
        let projectID = UUID()
        let sectionID = UUID()
        let otherProjectID = UUID()

        #expect(TaskFilter.project(projectID).replacingArchivedProject(projectID) == .upcoming)
        #expect(TaskFilter.projectSection(projectID, sectionID).replacingArchivedProject(projectID) == .upcoming)
        #expect(
            TaskFilter.projectSection(otherProjectID, sectionID).replacingArchivedProject(projectID)
                == .projectSection(otherProjectID, sectionID)
        )
    }

    @Test("Project and section titles resolve from current project tree")
    func projectAndSectionTitlesResolveFromCurrentProjectTree() {
        let projectID = UUID()
        let sectionID = UUID()

        let projectTitle = TaskFilter.project(projectID).resolvedDisplayTitle { id in
            id == projectID ? "Launch" : nil
        }
        let sectionTitle = TaskFilter.projectSection(projectID, sectionID).resolvedDisplayTitle(
            projectName: { id in id == projectID ? "Launch" : nil },
            sectionName: { _, id in id == sectionID ? "Build" : nil }
        )

        #expect(projectTitle == "Launch")
        #expect(sectionTitle == "Build")
    }

    @Test("Saved filter title resolves from current smart list store")
    func savedFilterTitleResolvesFromCurrentSmartListStore() {
        let filterID = UUID()

        let title = TaskFilter.savedFilter(filterID).resolvedDisplayTitle(
            savedFilterName: { id in id == filterID ? "Deep Work" : nil }
        )

        #expect(title == "Deep Work")
    }

    @Test("Inbox filter fetches no-date and future-snoozed tasks")
    @MainActor
    func inboxFilterFetchesInboxTasks() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext

        let noDate = TaskItem(title: "No date")
        noDate.createdAt = now.addingTimeInterval(-20)
        let today = TaskItem(title: "Today", dueAt: now)
        let snoozed = TaskItem(title: "Snoozed")
        snoozed.statusRaw = TaskStatus.snoozed.rawValue
        snoozed.snoozedUntil = now.addingTimeInterval(3_600)
        let expiredSnooze = TaskItem(title: "Expired")
        expiredSnooze.statusRaw = TaskStatus.snoozed.rawValue
        expiredSnooze.snoozedUntil = now.addingTimeInterval(-60)

        [noDate, today, snoozed, expiredSnooze].forEach(context.insert)
        try context.save()

        let inbox = try TaskListView.inboxTasks(now: now, modelContext: context)

        #expect(inbox.map { $0.title } == ["Snoozed", "No date"])
    }

    @Test("Top-level task data sources exclude subtasks")
    @MainActor
    func topLevelTaskDataSourcesExcludeSubtasks() throws {
        let now = Date(timeIntervalSinceReferenceDate: 900_000)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext

        let root = TaskItem(title: "Root")
        root.createdAt = now
        let child = TaskItem(title: "Child", parentTaskID: root.id)
        child.createdAt = now.addingTimeInterval(10)
        let doneRoot = TaskItem(title: "Done root", status: .done)
        let doneChild = TaskItem(title: "Done child", status: .done, parentTaskID: root.id)
        let taggedChild = TaskItem(title: "Tagged child", tags: ["work"], parentTaskID: root.id)

        [root, child, doneRoot, doneChild, taggedChild].forEach(context.insert)
        try context.save()

        let active = try TaskListView.tasks(status: nil, modelContext: context)
        let completed = try TaskListView.tasks(status: .done, modelContext: context)
        let tagged = TaskListView.rootTasks(
            from: try ByTagQuery().tasks(withTag: "work").apply(in: context)
        )

        #expect(active.map(\.title) == ["Root"])
        #expect(completed.map(\.title) == ["Done root"])
        #expect(tagged.isEmpty)
    }

    @Test("Subtask data source sorts children and counts direct completion")
    @MainActor
    func subtaskDataSourceSortsChildrenAndCountsDirectCompletion() throws {
        let now = Date(timeIntervalSinceReferenceDate: 901_000)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext

        let parent = TaskItem(title: "Parent")
        let later = TaskItem(title: "Later", parentTaskID: parent.id, orderIndex: 2)
        later.createdAt = now.addingTimeInterval(20)
        let first = TaskItem(title: "First", status: .done, parentTaskID: parent.id, orderIndex: 1)
        first.createdAt = now.addingTimeInterval(10)
        let grandchild = TaskItem(title: "Grandchild", status: .done, parentTaskID: first.id)
        let deleted = TaskItem(title: "Deleted", parentTaskID: parent.id, orderIndex: 0)
        deleted.deletedAt = now
        let unrelatedParent = TaskItem(title: "Unrelated parent")
        let unrelatedChild = TaskItem(title: "Unrelated child", parentTaskID: unrelatedParent.id)

        [parent, later, first, grandchild, deleted, unrelatedParent, unrelatedChild].forEach(context.insert)
        try context.save()

        let children = try SubtaskTreeDataSource.activeChildren(of: parent, modelContext: context)
        let progress = try SubtaskTreeDataSource.progress(parentID: parent.id, modelContext: context)
        let batchedProgress = try SubtaskTreeDataSource.progress(
            for: [parent, first, later],
            modelContext: context
        )

        #expect(children.map(\.title) == ["First", "Later"])
        #expect(progress == SubtaskProgress(done: 1, total: 2))
        #expect(batchedProgress[parent.id] == SubtaskProgress(done: 1, total: 2))
        #expect(batchedProgress[first.id] == SubtaskProgress(done: 1, total: 1))
        #expect(batchedProgress[later.id] == nil)
        #expect(batchedProgress[unrelatedParent.id] == nil)
    }

    @Test("Parent picker candidates stay root-scoped within the current project")
    @MainActor
    func parentPickerCandidatesStayRootScopedWithinProject() throws {
        let projectID = UUID()
        let otherProjectID = UUID()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext

        let task = TaskItem(title: "Current", projectID: projectID)
        let sameProjectRoot = TaskItem(title: "Same project", projectID: projectID)
        let otherProjectRoot = TaskItem(title: "Other project", projectID: otherProjectID)
        let unassignedRoot = TaskItem(title: "Unassigned")
        let nested = TaskItem(title: "Nested", parentTaskID: sameProjectRoot.id, projectID: projectID)
        let doneRoot = TaskItem(title: "Done", status: .done, projectID: projectID)

        [task, sameProjectRoot, otherProjectRoot, unassignedRoot, nested, doneRoot].forEach(context.insert)
        try context.save()

        let candidates = try TaskParentPickerDataSource.candidates(
            for: task,
            query: "",
            modelContext: context
        )

        #expect(candidates.map(\.title) == ["Same project"])
        #expect(try !TaskParentPickerDataSource.canAssign(task, toParent: nested, modelContext: context))
        #expect(try !TaskParentPickerDataSource.canAssign(task, toParent: doneRoot, modelContext: context))
    }

    @Test("Parent picker keeps unassigned tasks unassigned and rejects tasks with children")
    @MainActor
    func parentPickerKeepsUnassignedTasksUnassignedAndRejectsTasksWithChildren() throws {
        let projectID = UUID()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext

        let task = TaskItem(title: "Current")
        let unassignedRoot = TaskItem(title: "Unassigned root")
        let projectRoot = TaskItem(title: "Project root", projectID: projectID)
        let branch = TaskItem(title: "Branch")
        let branchChild = TaskItem(title: "Branch child", parentTaskID: branch.id)

        [task, unassignedRoot, projectRoot, branch, branchChild].forEach(context.insert)
        try context.save()

        let candidates = try TaskParentPickerDataSource.candidates(
            for: task,
            query: "",
            modelContext: context
        )
        let branchCandidates = try TaskParentPickerDataSource.candidates(
            for: branch,
            query: "",
            modelContext: context
        )

        #expect(candidates.map(\.title) == ["Branch", "Unassigned root"])
        #expect(try !TaskParentPickerDataSource.canAssign(task, toParent: projectRoot, modelContext: context))
        #expect(branchCandidates.isEmpty)
        #expect(try !TaskParentPickerDataSource.canAssign(branch, toParent: unassignedRoot, modelContext: context))
    }

    @Test("Parent assignment aligns section with parent scope")
    @MainActor
    func parentAssignmentAlignsSectionWithParentScope() throws {
        let projectID = UUID()
        let sectionID = UUID()
        let originalSectionID = UUID()
        let stamp = Date(timeIntervalSinceReferenceDate: 902_000)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let task = TaskItem(title: "Current", projectID: projectID, sectionID: originalSectionID)
        let parent = TaskItem(title: "Parent", projectID: projectID, sectionID: sectionID)

        [task, parent].forEach(context.insert)
        try context.save()

        let assigned = try TaskParentPickerDataSource.assign(
            task: task,
            toParent: parent,
            repository: repository,
            modelContext: context
        )

        #expect(assigned)
        #expect(task.parentTaskID == parent.id)
        #expect(task.projectID == parent.projectID)
        #expect(task.sectionID == parent.sectionID)
    }

    @Test("New subtask action inherits parent project and section")
    @MainActor
    func newSubtaskActionInheritsParentProjectAndSection() throws {
        let projectID = UUID()
        let sectionID = UUID()
        let stamp = Date(timeIntervalSinceReferenceDate: 902_500)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let parent = TaskItem(title: "Parent", projectID: projectID, sectionID: sectionID)
        context.insert(parent)
        try context.save()

        let child = try TaskSubtaskAction.createChild(under: parent, repository: repository)

        #expect(child.title == "New subtask")
        #expect(child.parentTaskID == parent.id)
        #expect(child.projectID == projectID)
        #expect(child.sectionID == sectionID)
    }

    @Test("New subtask action rejects done parents")
    @MainActor
    func newSubtaskActionRejectsDoneParents() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 902_750)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let parent = TaskItem(title: "Parent", status: .done)
        context.insert(parent)
        try context.save()

        #expect(throws: TaskSubtaskActionError.parentNotOpen(parentID: parent.id)) {
            _ = try TaskSubtaskAction.createChild(under: parent, repository: repository)
        }

        let rows = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(rows.map(\.title) == ["Parent"])
    }

    @Test("Subtask-aware completion cascades parent with open descendants")
    @MainActor
    func subtaskAwareCompletionCascadesParentWithOpenDescendants() throws {
        let stamp = Date(timeIntervalSinceReferenceDate: 903_000)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TaskItem.self, configurations: config)
        let context = container.mainContext
        let repository = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { stamp })

        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        let grandchild = TaskItem(title: "Grandchild", parentTaskID: child.id)

        [parent, child, grandchild].forEach(context.insert)
        try context.save()

        try TaskCompletionAction.completeOrCascade(parent, repository: repository)

        #expect(parent.status == .done)
        #expect(child.status == .done)
        #expect(grandchild.status == .done)
        #expect(parent.lastCompletedAt == stamp)
        #expect(child.lastCompletedAt == stamp)
        #expect(grandchild.lastCompletedAt == stamp)
    }

    @Test("Project filters fetch non-deleted project and section tasks")
    @MainActor
    func projectFiltersFetchProjectAndSectionTasks() throws {
        let schema = Schema([TaskItem.self, Project.self, Section.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let project = Project(name: "Launch", color: "gold")
        let section = Section(projectID: project.id, name: "Build", orderIndex: 1)
        let rootTask = TaskItem(title: "Root", projectID: project.id)
        rootTask.createdAt = Date(timeIntervalSinceReferenceDate: 10)
        let sectionTask = TaskItem(title: "Section", projectID: project.id, sectionID: section.id)
        sectionTask.createdAt = Date(timeIntervalSinceReferenceDate: 20)
        let childTask = TaskItem(title: "Child", parentTaskID: rootTask.id, projectID: project.id)
        let deleted = TaskItem(title: "Deleted", projectID: project.id, sectionID: section.id)
        deleted.deletedAt = Date(timeIntervalSinceReferenceDate: 30)
        let other = TaskItem(title: "Other", projectID: UUID())

        context.insert(project)
        context.insert(section)
        [rootTask, sectionTask, childTask, deleted, other].forEach(context.insert)
        try context.save()

        let projectTasks = try TaskListView.projectTasks(
            projectID: project.id,
            sectionID: nil,
            modelContext: context
        )
        let sectionTasks = try TaskListView.projectTasks(
            projectID: project.id,
            sectionID: section.id,
            modelContext: context
        )

        #expect(projectTasks.map(\.title) == ["Root", "Section"])
        #expect(sectionTasks.map(\.title) == ["Section"])
    }
}
