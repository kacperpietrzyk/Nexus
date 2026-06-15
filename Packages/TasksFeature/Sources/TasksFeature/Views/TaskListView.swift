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
    @Environment(\.taskRepository) private var repository

    public let filter: TaskFilter
    public let now: Date
    public let onSelect: ((TaskItem) -> Void)?

    @State var overdue: [TaskItem] = []
    @State var today: [TaskItem] = []
    @State var noDate: [TaskItem] = []
    @State var flatList: [TaskItem] = []
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var subtaskProgressByTaskID: [UUID: SubtaskProgress] = [:]
    @State private var parentPickerTarget: TaskItem?
    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var error: String?
    @State var refinement = TaskListRefinement()
    @State var refinementLabels: [TaskLabel] = []

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
            TaskListFilterBar(refinement: $refinement, availableLabels: refinementLabels)
        }
        .task(id: filter) { reload() }
        .task { loadRefinementLabels() }
        .onChange(of: now) { _, _ in reload() }
        .onChange(of: refinement) { _, _ in reload() }
        .reloadOnStoreChange { reload() }
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
            case .all, .upcoming, .completed, .templates, .byTag:
                // MP-2 motion pass: staggered row enter via .nexusAppear(i)
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            case .inbox:
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            case .project, .projectSection, .cycle:
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

    /// Liquid empty state (calm, title + one line) — same idiom as
    /// `LiquidEmptyState`, plus the title line the per-filter resolver carries.
    private func taskEmptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: systemImage)
                // 22 pt hero glyph — matches LiquidEmptyState's calibration.
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: DS.Space.xs) {
                Text(title)
                    .font(DS.FontToken.section)
                    .foregroundStyle(DS.ColorToken.textPrimary)

                Text(message)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, DS.Space.xxxl)
        .padding(.bottom, 118)
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(DS.FontToken.metadata)
            // Error legibility is carried by contrast/weight, not color.
            .foregroundStyle(DS.ColorToken.textPrimary)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(containerBackground)
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
            .listRowBackground(containerBackground)
        } else if flatList.isEmpty {
            ContentUnavailableView(
                "No matching tasks",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("This Smart List has no open root tasks right now.")
            )
            .listRowBackground(containerBackground)
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
                sectionHeader("TODAY")
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
                sectionHeader(title.uppercased())
            }
        }
    }

    /// Tracked-caps Liquid section header (01_FOUNDATIONS §Gęstość informacji).
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .tracking(0.8)
            .foregroundStyle(DS.ColorToken.textTertiary)
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
        .listRowBackground(containerBackground)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(item) }
        .swipeActions(edge: .leading) {
            Button {
                toggleDone(item)
            } label: {
                Label(item.status == .done ? "Reopen" : "Done", systemImage: "checkmark.circle")
            }
            // Solid dark swipe fill (backgroundElevated) so the white system
            // label stays legible; glass tokens are translucent and would let
            // the row bleed through mid-swipe.
            .tint(DS.ColorToken.backgroundElevated)
        }
        .swipeActions(edge: .trailing) {
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
        .taskAssistContextMenu(for: item) { actions in
            if item.isTemplate {
                Button("New Task from Template") { instantiateTemplate(item) }
                // I-D1: no complete/snooze/subtask affordances on an inert blueprint;
                // delete stays available via the leading swipe + list delete flows.
            } else {
                Button(item.status == .done ? "Reopen" : "Mark done") { toggleDone(item) }
                Button("Save as Template") { saveAsTemplate(item) }
                Button("Subtask of…") { parentPickerTarget = item }
                Button("Snooze 1h") { snooze(item, by: .oneHour) }
                Button("Snooze until tomorrow") { snooze(item, by: .tomorrow) }
                TaskAssistMenuSection(actions: actions)
            }
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
    private func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let repository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: repository)
            withAnimation(DS.Motion.standard) { reload() }
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
            withAnimation(DS.Motion.standard) { reload() }
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
    private func saveAsTemplate(_ item: TaskItem) {
        guard let repository else { return }
        do {
            _ = try TemplateInstantiator(tasks: repository).saveAsTemplate(item)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func instantiateTemplate(_ item: TaskItem) {
        guard let repository else { return }
        do {
            _ = try TemplateInstantiator(tasks: repository).instantiate(item)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Loads the Today view's three buckets; split out of `reload()` for the
    /// function-body lint budget.
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
        noDate = Self.rootTasks(
            from: try query.noDate(excludingProjectIDs: archivedProjectIDs)
                .apply(in: modelContext)
        )
    }
}
