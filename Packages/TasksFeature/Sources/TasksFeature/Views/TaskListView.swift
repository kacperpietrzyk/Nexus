import Combine
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Three-bucket list when filter == .today (Overdue / Today / No date),
/// flat list otherwise. Manual fetch via `TaskBucket.apply(in:)` because
/// `TaskBucket` carries an in-memory `postFilter` closure that SwiftData
/// `@Query` can't represent.
public struct TaskListView: View {

    // `internal` (not private) so the refinement extension in
    // TaskListRefinement.swift can post-filter the resolved arrays without
    // bloating this file's type body past the lint budget.
    @Environment(\.modelContext) var modelContext
    // `internal` so TaskListView+BulkActions.swift can call repository methods.
    @Environment(\.taskRepository) var repository

    public let filter: TaskFilter
    public let now: Date
    public let onSelect: ((TaskItem) -> Void)?

    @State var overdue: [TaskItem] = []
    @State var today: [TaskItem] = []
    @State var noDate: [TaskItem] = []
    @State var flatList: [TaskItem] = []
    // Windowed-loading cursor for the high-volume `.all`/`.today` filters. Only
    // those two (DB-sorted) filters page; everything else loads fully and leaves
    // this untouched. See `TaskListPageState`.
    @State var pageState = TaskListPageState()
    @State var expandedTaskIDs: Set<UUID> = []
    // `internal` so the +Paging extension can refresh progress after an append.
    @State var subtaskProgressByTaskID: [UUID: SubtaskProgress] = [:]
    @State var parentPickerTarget: TaskItem?
    @State var cascadePrompt: CascadeCompletionPrompt?
    // `internal` so the +Paging extension can surface a load-more failure.
    @State var error: String?
    @State var refinement = TaskListRefinement()
    @AppStorage(NexusPreferences.Keys.taskListGroupBy) private var groupByRaw = TaskGroupBy.none.rawValue
    @State var projectsByID: [UUID: Project] = [:]
    @State var refinementLabels: [TaskLabel] = []
    // Memoized labeled-task-id resolution (FIX 3a): only re-queries
    // LinkRepository when `refinement.labelID` changes.
    @State var labeledTaskIDCache = LabeledTaskIDCache()
    // Multi-select / bulk actions
    // `internal` so TaskListView+BulkActions.swift extension can read/write these.
    @State var selection = SelectionModel<UUID>()
    @State var undo = UndoController()
    @State var bulkMovePickerPresented = false
    @State var bulkMoveActiveProjects: [Project] = []
    // Per-row context-menu project picker (single task move)
    @State var contextMoveTarget: TaskItem?
    @State var contextMoveActiveProjects: [Project] = []

    public init(
        filter: TaskFilter,
        now: Date = .now,
        onSelect: ((TaskItem) -> Void)? = nil
    ) {
        self.filter = filter
        self.now = now
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            switch emptyState {
            case .empty(let title, let systemImage, let message):
                taskEmptyState(title: title, systemImage: systemImage, message: message)
            case .none:
                taskListContent
            }
        }
        .background(containerBackground)
        #if os(iOS)
        // Touch Liquid pass: the transparent list sits on a single light-glass
        // panel over the shell aurora (mirrors the macOS shell content card and
        // the `LiquidTodayScreen` card family), inset so the aurora reads at the
        // margins. macOS keeps the shell-painted panel (no double card).
        .background {
            Color.clear
            .liquidLightCard(cornerRadius: DS.Radius.l)
            .padding(.horizontal, DS.Space.s)
            .padding(.bottom, DS.Space.s)
        }
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            TaskListFilterBar(refinement: $refinement, availableLabels: refinementLabels, selection: selection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BulkActionBar(
                model: selection,
                allIDs: visibleRootTasks.map(\.id),
                actions: bulkActions
            )
        }
        .undoToast(undo)
        // Global ⌘A: publish this list's "select all" into the focused scene so
        // the shell's menu-bar command can route ⌘A here. macOS mounts exactly
        // one list destination at a time, so the default `isActive: true` is
        // correct; the published action enters selection mode + selects every
        // visible root task.
        .selectAllCommandTarget(in: selection, ids: visibleRootTasks.map(\.id))
        // Palette "Select All Items" path; the menu-bar ⌘A uses the focused
        // value above. macOS / iPad mount one list surface at a time.
        .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
            selection.enterSelection()
            selection.selectAll(visibleRootTasks.map(\.id))
        }
        // Select/Done entry now lives in the in-content `TaskListFilterBar`
        // (the macOS shell paints its own NexusTopBar, so `.toolbar` items never
        // surfaced); long-press on any row is the secondary entry point on iOS.
        .task(id: filter) { reload() }
        .task { loadRefinementLabels() }
        .onChange(of: now) { _, _ in reload() }
        .onChange(of: refinement) { _, _ in reload() }
        .reloadOnStoreChange {
            // A store change can mutate the label→task graph without changing the
            // selected label, so drop the memoized id-set before re-filtering.
            labeledTaskIDCache.invalidate()
            reload()
        }
        .sheet(item: $parentPickerTarget) { item in
            ParentTaskPickerSheet(task: item) {
                reload()
            }
        }
        .sheet(isPresented: $bulkMovePickerPresented) {
            ProjectPickerSheet(
                projects: bulkMoveActiveProjects,
                title: "Move \(selection.count) tasks to…"
            ) { projectID in
                bulkMove(toProject: projectID)
                bulkMovePickerPresented = false
            } onCancel: {
                bulkMovePickerPresented = false
            }
        }
        .sheet(item: $contextMoveTarget) { task in
            ProjectPickerSheet(
                projects: contextMoveActiveProjects,
                title: "Move to project"
            ) { projectID in
                moveToProject(projectID, for: task)
                contextMoveTarget = nil
            } onCancel: {
                contextMoveTarget = nil
            }
        }
        .cascadeCompletionConfirmation($cascadePrompt) { prompt in
            confirmCascade(prompt)
        }
    }

    private var emptyState: TaskListEmptyState {
        TaskListEmptyState.resolve(
            filter: filter,
            isEmpty: listIsEmpty,
            hasError: error != nil
        )
    }

}

// MARK: - Reload, mutations and bulk-action state

extension TaskListView {

    // `internal` so TaskListView+BulkActions.swift can call reload() after mutations.
    @MainActor
    func reload() {
        do {
            // A reload re-resolves the data set from scratch, so the windowed
            // cursors must reset too — otherwise a `now` tick or store-change
            // refresh would keep a stale "already loaded N" cursor and the first
            // page would skip rows.
            pageState.reset()
            let archivedProjectIDs =
                (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
            switch filter {
            case .all where isWindowing:
                flatList = try loadFirstFlatPage()
            case .all:
                flatList = try Self.tasks(status: nil, modelContext: modelContext)
            case .today:
                try reloadTodayBuckets(archivedProjectIDs: archivedProjectIDs)
            case .upcoming:
                flatList = Self.rootTasks(
                    from: try UpcomingQuery()
                        .next(days: 7, from: now, excludingProjectIDs: archivedProjectIDs)
                        .apply(in: modelContext)
                )
            case .inbox:
                flatList = try Self.inboxTasks(now: now, modelContext: modelContext)
            case .completed:
                flatList = try Self.tasks(status: .done, modelContext: modelContext)
            case .templates:
                flatList = try Self.templateTasks(modelContext: modelContext)
            case .byTag(let tag):
                flatList = Self.rootTasks(
                    from: try ByTagQuery().tasks(withTag: tag).apply(in: modelContext)
                )
            case .project(let projectID):
                flatList = try Self.projectTasks(projectID: projectID, sectionID: nil, modelContext: modelContext)
            case .projectSection(let projectID, let sectionID):
                flatList = try Self.projectTasks(
                    projectID: projectID,
                    sectionID: sectionID,
                    modelContext: modelContext
                )
            case .savedFilter(let filterID):
                flatList = try Self.savedFilterTasks(
                    filterID: filterID,
                    now: now,
                    modelContext: modelContext
                )
            case .cycle(let cycleID):
                flatList = try Self.cycleTasks(cycleID: cycleID, modelContext: modelContext)
            }
            applyRefinement()
            subtaskProgressByTaskID = try SubtaskTreeDataSource.progress(
                for: visibleRootTasks,
                modelContext: modelContext
            )
            projectsByID = Dictionary(
                loadActiveProjects().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    var visibleRootTasks: [TaskItem] {
        switch filter {
        case .today:
            return overdue + today + noDate
        case .savedFilter:
            return flatList
        default:
            return flatList
        }
    }

    /// Bulk actions shown in the `BulkActionBar` when `selection.hasSelection`.
    @MainActor
    var bulkActions: [BulkAction] {
        var actions: [BulkAction] = []
        actions.append(BulkAction(label: "Complete", systemImage: "checkmark.circle") { [self] in bulkComplete() })
        actions.append(BulkAction(label: "Snooze 1h", systemImage: "clock") { [self] in bulkSnooze(by: .oneHour) })
        actions.append(BulkAction(label: "Tomorrow", systemImage: "sun.haze") { [self] in bulkSnooze(by: .tomorrow) })
        actions.append(BulkAction(label: "Pin", systemImage: "pin") { [self] in bulkPin() })
        actions.append(BulkAction(label: "Move", systemImage: "folder") { [self] in bulkMovePresent() })
        actions.append(BulkAction(label: "Copy", systemImage: "doc.on.doc") { [self] in bulkCopyAsMarkdown() })
        actions.append(BulkAction(label: "Delete", systemImage: "trash", role: .destructive) { [self] in bulkDelete() })
        return actions
    }

    @MainActor
    private func bulkMovePresent() {
        bulkMoveActiveProjects = loadActiveProjects()
        bulkMovePickerPresented = true
    }

    var isSavedFilter: Bool {
        if case .savedFilter = filter { return true }
        return false
    }

    /// Render-time grouping selection. Lives OUTSIDE `refinement` on purpose:
    /// changing it re-sections already-fetched rows and must NOT trigger a
    /// `reload()` (which `refinement` changes do).
    var groupBy: Binding<TaskGroupBy> {
        Binding(
            get: { TaskGroupBy(rawValue: groupByRaw) ?? .none },
            set: { groupByRaw = $0.rawValue }
        )
    }

    /// Whether the resolved data set for the current filter has zero rows.
    var listIsEmpty: Bool {
        switch filter {
        case .today: return overdue.isEmpty && today.isEmpty && noDate.isEmpty
        default: return flatList.isEmpty
        }
    }

    @MainActor
    func toggleExpansion(for item: TaskItem) {
        if expandedTaskIDs.contains(item.id) {
            expandedTaskIDs.remove(item.id)
        } else {
            expandedTaskIDs.insert(item.id)
        }
    }

    @MainActor
    func toggleDone(_ item: TaskItem) {
        guard let repository, !item.isTemplate else { return }
        do {
            if item.status == .done {
                try repository.reopen(item)
            } else {
                try TaskCompletionAction.complete(item, repository: repository)
            }
            // Animate the row leaving/changing the list — completion is the
            // most-triggered mutation and must not pop. Load/filter reloads stay
            // unwrapped so the per-row `.nexusAppear` stagger owns those.
            withAnimation(DS.Motion.standard) { reload() }
        } catch let error as TaskItemRepositoryError {
            if case .parentHasOpenSubtasks(let parentID, let openCount) = error, parentID == item.id {
                cascadePrompt = CascadeCompletionPrompt(task: item, openCount: openCount)
            } else {
                self.error = String(describing: error)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let repository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: repository)
            withAnimation(DS.Motion.standard) { reload() }
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    func moveToday(from offsets: IndexSet, to destination: Int) {
        guard let repository else { return }
        // Renumber the whole visible Today order so the reorder persists and is
        // reflected by `TodayQuery.today`'s manual-order comparator. A single
        // midpoint write isn't enough here: un-reordered rows have a nil
        // `orderIndex`, so the moved row had no neighbours to bound it and the
        // change never showed. `reorder` assigns sequential indices in one save
        // without the per-task notification churn of `update`.
        var reordered = today
        reordered.move(fromOffsets: offsets, toOffset: destination)
        do {
            try repository.reorder(reordered)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    func snooze(_ item: TaskItem, by offset: SnoozeOffset) {
        guard let repository else { return }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let until: Date
        switch offset {
        case .oneHour:
            until = now.addingTimeInterval(60 * 60)
        case .tomorrow:
            let startOfTomorrow =
                calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            until = startOfTomorrow
        }
        do {
            try repository.snooze(item, until: until)
            withAnimation(DS.Motion.standard) { reload() }
        } catch {
            self.error = String(describing: error)
        }
    }

    enum SnoozeOffset { case oneHour, tomorrow }
}

// MARK: - Template actions, swipe actions, section buckets

extension TaskListView {
    @MainActor
    func saveAsTemplate(_ item: TaskItem) {
        guard let repository else { return }
        do {
            _ = try TemplateInstantiator(tasks: repository).saveAsTemplate(item)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    func instantiateTemplate(_ item: TaskItem) {
        guard let repository else { return }
        do {
            _ = try TemplateInstantiator(tasks: repository).instantiate(item)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    func deleteTemplate(_ item: TaskItem) {
        guard let repository, item.isTemplate else { return }
        do {
            try repository.softDelete(item)
            withAnimation(DS.Motion.standard) { reload() }
        } catch {
            self.error = String(describing: error)
        }
    }

    @ViewBuilder
    func leadingSwipeActions(for item: TaskItem) -> some View {
        // Templates are inert blueprints — no Done. Everything else gets the
        // complete/reopen toggle.
        if !item.isTemplate {
            Button {
                toggleDone(item)
            } label: {
                Label(item.status == .done ? "Reopen" : "Done", systemImage: "checkmark.circle")
            }
            // Solid dark swipe fill (backgroundElevated) so the white system label
            // stays legible; glass tokens are translucent and would let the row
            // bleed through mid-swipe.
            .tint(DS.ColorToken.backgroundElevated)
        }
    }

    @ViewBuilder
    func trailingSwipeActions(for item: TaskItem) -> some View {
        if item.isTemplate {
            // Templates have no snooze; the trailing edge is their delete path.
            Button(role: .destructive) {
                deleteTemplate(item)
            } label: {
                Label("Delete Template", systemImage: "trash")
            }
        } else {
            Button {
                snooze(item, by: .oneHour)
            } label: {
                Label("1h", systemImage: "clock")
            }
            // Solid dark swipe fill (see leading edge).
            .tint(DS.ColorToken.backgroundElevated)
            Button {
                snooze(item, by: .tomorrow)
            } label: {
                Label("Tomorrow", systemImage: "sun.haze")
            }
            .tint(DS.ColorToken.backgroundElevated)
        }
    }

    /// Loads the Today view's three buckets; split out of `reload()` for the
    /// function-body lint budget. The `overdue`/`today` buckets are tiny (only the
    /// dated tasks) so they always load fully; only the high-volume `noDate` bucket
    /// is windowed (and only when `isWindowing`).
    @MainActor
    private func reloadTodayBuckets(archivedProjectIDs: Set<UUID>) throws {
        let query = TodayQuery()
        overdue = Self.rootTasks(
            from: try query.overdue(now: now, excludingProjectIDs: archivedProjectIDs)
                .apply(in: modelContext)
        )
        today = Self.rootTasks(
            from: try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
                .apply(in: modelContext)
        )
        if isWindowing {
            noDate = try loadFirstNoDatePage(archivedProjectIDs: archivedProjectIDs)
        } else {
            noDate = Self.rootTasks(
                from: try query.noDate(excludingProjectIDs: archivedProjectIDs)
                    .apply(in: modelContext)
            )
        }
    }
}
