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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    public let filter: TaskFilter
    public let now: Date
    public let onSelect: ((TaskItem) -> Void)?

    @State private var overdue: [TaskItem] = []
    @State private var today: [TaskItem] = []
    @State private var noDate: [TaskItem] = []
    @State private var flatList: [TaskItem] = []
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var subtaskProgressByTaskID: [UUID: SubtaskProgress] = [:]
    @State private var parentPickerTarget: TaskItem?
    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var error: String?

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
        .background(NexusColor.Background.base)
        .task(id: filter) { reload() }
        .onChange(of: now) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
        .sheet(item: $parentPickerTarget) { item in
            ParentTaskPickerSheet(task: item) {
                reload()
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

    private var taskListContent: some View {
        List {
            if let error, !isSavedFilter {
                errorRow(error)
            }

            switch filter {
            case .today:
                section("Overdue", items: overdue)
                todaySection
                section("No date", items: noDate)
            case .all, .upcoming, .completed, .byTag:
                // MP-2 motion pass: staggered row enter via .nexusAppear(i)
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            case .inbox:
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            case .project, .projectSection:
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            case .savedFilter:
                savedFilterContent
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func taskEmptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 35, weight: .medium))
                .foregroundStyle(NexusColor.Text.muted)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text(title)
                    .font(NexusType.h2)
                    .foregroundStyle(NexusColor.Text.primary)

                Text(message)
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 32)
        .padding(.bottom, 118)
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            // MP-2 burned: error text renders via primary ink (hue symbol retired;
            // error legibility is carried by contrast/weight, not color).
            .foregroundStyle(NexusColor.Text.primary)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(NexusColor.Background.base)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var savedFilterContent: some View {
        if let error {
            ContentUnavailableView(
                "Smart List unavailable",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(error)
            )
            .listRowBackground(NexusColor.Background.base)
        } else if flatList.isEmpty {
            ContentUnavailableView(
                "No matching tasks",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("This Smart List has no open root tasks right now.")
            )
            .listRowBackground(NexusColor.Background.base)
        } else {
            ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                row(for: item, appearIndex: i)
            }
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        if !today.isEmpty {
            Section {
                // MP-2 motion pass: staggered row enter via .nexusAppear(i)
                ForEach(Array(today.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
                .onMove { from, to in moveToday(from: from, to: to) }
            } header: {
                Text("TODAY")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [TaskItem]) -> some View {
        if !items.isEmpty {
            Section {
                // MP-2 motion pass: staggered row enter via .nexusAppear(i)
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            } header: {
                Text(title.uppercased())
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }

    @ViewBuilder
    private func row(for item: TaskItem, appearIndex: Int? = nil) -> some View {
        // MP-2 motion pass: only the row itself gets the staggered enter — the
        // subtask list expands on tap, not on appear, so it stays unindexed.
        if let appearIndex {
            rowView(for: item).nexusAppear(appearIndex)
        } else {
            rowView(for: item)
        }
        if expandedTaskIDs.contains(item.id) {
            SubtaskListView(
                parent: item,
                now: now,
                expandedTaskIDs: $expandedTaskIDs,
                onSelect: onSelect
            )
        }
    }

    private func rowView(for item: TaskItem) -> some View {
        TaskRowView(
            task: item,
            now: now,
            subtaskProgress: subtaskProgressByTaskID[item.id],
            isSubtasksExpanded: expandedTaskIDs.contains(item.id),
            showsDefaultTaskAssistMenu: false,
            onToggleSubtasks: { toggleExpansion(for: item) },
            onToggleDone: { toggleDone(item) },
            onSnooze: { snooze(item, by: .oneHour) }
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(NexusColor.Background.base)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(item) }
        .swipeActions(edge: .leading) {
            Button {
                toggleDone(item)
            } label: {
                Label(item.status == .done ? "Reopen" : "Done", systemImage: "checkmark.circle")
            }
            // MP-2 canonical achromatic swipe fill: controlHover (0x1E1F25) is a
            // solid dark control surface so the white system label stays legible
            // (Text.primary would be white-on-white). Zero hue. Propagates.
            .tint(NexusColor.Background.controlHover)
        }
        .swipeActions(edge: .trailing) {
            Button {
                snooze(item, by: .oneHour)
            } label: {
                Label("1h", systemImage: "clock")
            }
            // MP-2 canonical achromatic swipe fill (see leading edge).
            .tint(NexusColor.Background.controlHover)
            Button {
                snooze(item, by: .tomorrow)
            } label: {
                Label("Tomorrow", systemImage: "sun.haze")
            }
            .tint(NexusColor.Background.controlHover)
        }
        .taskAssistContextMenu(for: item) { actions in
            Button(item.status == .done ? "Reopen" : "Mark done") { toggleDone(item) }
            Button("Subtask of…") { parentPickerTarget = item }
            Button("Snooze 1h") { snooze(item, by: .oneHour) }
            Button("Snooze until tomorrow") { snooze(item, by: .tomorrow) }
            TaskAssistMenuSection(actions: actions)
        }
    }

    @MainActor
    private func reload() {
        do {
            let archivedProjectIDs =
                (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
            switch filter {
            case .all:
                flatList = try Self.tasks(status: nil, modelContext: modelContext)
            case .today:
                let query = TodayQuery()
                overdue = Self.rootTasks(
                    from: try query.overdue(now: now, excludingProjectIDs: archivedProjectIDs)
                        .apply(in: modelContext)
                )
                today = Self.rootTasks(
                    from: try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
                        .apply(in: modelContext)
                )
                noDate = Self.rootTasks(
                    from: try query.noDate(excludingProjectIDs: archivedProjectIDs)
                        .apply(in: modelContext)
                )
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
            }
            subtaskProgressByTaskID = try SubtaskTreeDataSource.progress(
                for: visibleRootTasks,
                modelContext: modelContext
            )
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private var visibleRootTasks: [TaskItem] {
        switch filter {
        case .today:
            return overdue + today + noDate
        case .savedFilter:
            return flatList
        default:
            return flatList
        }
    }

    private var isSavedFilter: Bool {
        if case .savedFilter = filter {
            return true
        }
        return false
    }

    /// Whether the resolved data set for the current filter has zero rows.
    /// Drives `TaskListEmptyState.resolve`. `.today` aggregates its three
    /// buckets; every other filter uses the flat list. `.savedFilter` is
    /// included for completeness but the resolver short-circuits it.
    private var listIsEmpty: Bool {
        switch filter {
        case .today:
            return overdue.isEmpty && today.isEmpty && noDate.isEmpty
        default:
            return flatList.isEmpty
        }
    }

    @MainActor
    private func toggleExpansion(for item: TaskItem) {
        if expandedTaskIDs.contains(item.id) {
            expandedTaskIDs.remove(item.id)
        } else {
            expandedTaskIDs.insert(item.id)
        }
    }

    @MainActor
    private func toggleDone(_ item: TaskItem) {
        guard let repository else { return }
        do {
            if item.status == .done {
                try repository.reopen(item)
            } else {
                try TaskCompletionAction.complete(item, repository: repository)
            }
            reload()
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
    private func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let repository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: repository)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func moveToday(from offsets: IndexSet, to destination: Int) {
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
    private func snooze(_ item: TaskItem, by offset: SnoozeOffset) {
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
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    private enum SnoozeOffset {
        case oneHour
        case tomorrow
    }
}

extension TaskListView {
    @MainActor
    static func rootTasks(from tasks: [TaskItem]) -> [TaskItem] {
        SubtaskTreeDataSource.rootTasks(from: tasks)
    }

    @MainActor
    static func tasks(status: TaskStatus?, modelContext: ModelContext) throws -> [TaskItem] {
        if let status {
            let rawStatus = status.rawValue
            let predicate = #Predicate<TaskItem> { task in
                task.deletedAt == nil && task.statusRaw == rawStatus && task.parentTaskID == nil
            }
            let descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\TaskItem.dueAt, order: .forward),
                    SortDescriptor(\TaskItem.createdAt, order: .reverse),
                ]
            )
            return try modelContext.fetch(descriptor)
        }

        let doneStatus = TaskStatus.done.rawValue
        let predicate = #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.statusRaw != doneStatus && task.parentTaskID == nil
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\TaskItem.dueAt, order: .forward),
                SortDescriptor(\TaskItem.createdAt, order: .reverse),
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    @MainActor
    static func projectTasks(
        projectID: UUID,
        sectionID: UUID?,
        modelContext: ModelContext
    ) throws -> [TaskItem] {
        if let sectionID {
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.projectID == projectID
                        && task.sectionID == sectionID
                        && task.deletedAt == nil
                }
            )
            return rootTasks(from: try modelContext.fetch(descriptor)).sorted(by: Self.assignmentOrder)
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.projectID == projectID && task.deletedAt == nil
            }
        )
        return rootTasks(from: try modelContext.fetch(descriptor)).sorted(by: Self.assignmentOrder)
    }

    static func assignmentOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.orderIndex, rhs.orderIndex) {
        case (let left?, let right?) where left != right:
            return left < right
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            return lhs.createdAt < rhs.createdAt
        }
    }

    @MainActor
    static func inboxTasks(now: Date, modelContext: ModelContext) throws -> [TaskItem] {
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let noDate = try TodayQuery()
            .noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let snoozedStatus = TaskStatus.snoozed.rawValue
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil && task.statusRaw == snoozedStatus && task.parentTaskID == nil
            },
            sortBy: [SortDescriptor(\TaskItem.snoozedUntil, order: .forward)]
        )
        let snoozed = try modelContext.fetch(descriptor)
            .filter { ($0.snoozedUntil ?? .distantPast) > now }
            .filter { task in
                guard let projectID = task.projectID else { return true }
                return !archivedProjectIDs.contains(projectID)
            }
        return (rootTasks(from: noDate) + snoozed).sorted { lhs, rhs in
            switch (lhs.snoozedUntil, rhs.snoozedUntil) {
            case (let lhsDate?, let rhsDate?):
                return lhsDate < rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }
}

extension TaskListView {
    @MainActor
    static func savedFilterTasks(
        filterID: UUID,
        now: Date,
        modelContext: ModelContext
    ) throws -> [TaskItem] {
        let repository = SavedFilterRepository(context: modelContext, now: { now })
        guard let filter = try repository.find(filterID) else {
            throw SavedFilterTaskListError.missing
        }

        do {
            return rootTasks(from: try repository.apply(filter, now: now))
        } catch is DecodingError {
            throw SavedFilterTaskListError.corrupt
        }
    }
}

private enum SavedFilterTaskListError: LocalizedError, CustomStringConvertible {
    case missing
    case corrupt

    var errorDescription: String? {
        switch self {
        case .missing:
            return "This Smart List no longer exists."
        case .corrupt:
            return "This Smart List cannot be decoded. Delete it and save the filter again."
        }
    }

    var description: String {
        errorDescription ?? "Smart List error."
    }
}
