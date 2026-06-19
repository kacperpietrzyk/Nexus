import NexusCore
import NexusUI
import SwiftUI

// MARK: - View-building helpers for TaskListView (split for file-length budget).
//
// Contains the content layout (`taskListContent`, `taskEmptyState`, section
// builders, `row(for:)`, and `rowView(for:)`). These are pure `View`-value
// helpers; all mutations remain in `TaskListView+BulkActions.swift` and the
// reload extension.

extension TaskListView {

    var taskListContent: some View {
        List {
            if let error, !isSavedFilter {
                errorRow(error)
            }

            switch filter {
            case .today:
                section("Overdue", items: overdue)
                todaySection
                noDateSection
            case .all where isWindowing:
                // Windowed flat list: capped stagger + a prefetch trigger near the
                // tail. `windowedRow` appends the next page on appear.
                ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                    windowedRow(for: item, index: i, loadedCount: flatList.count)
                }
            case .all, .upcoming, .completed, .templates, .byTag, .inbox:
                groupedFlatContent
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

    /// Liquid empty state (calm, title + one line).
    func taskEmptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: systemImage)
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

    func errorRow(_ message: String) -> some View {
        Text(message)
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(containerBackground)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    var groupedFlatContent: some View {
        let sections = taskGroupSections(
            flatList, by: groupBy.wrappedValue, projectsByID: projectsByID,
            now: now, calendar: Self.groupingCalendar
        )
        if groupBy.wrappedValue == .none {
            ForEach(Array(flatList.enumerated()), id: \.element.id) { i, item in
                row(for: item, appearIndex: i)
            }
        } else {
            ForEach(sections, id: \.key) { group in
                section(group.key, items: group.items)
            }
        }
    }

    static var groupingCalendar: Calendar {
        var c = Calendar(identifier: .iso8601); c.timeZone = .current; return c
    }

    @ViewBuilder
    var savedFilterContent: some View {
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
    var todaySection: some View {
        if !today.isEmpty {
            Section {
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
    func section(_ title: String, items: [TaskItem]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    row(for: item, appearIndex: i)
                }
            } header: {
                sectionHeader(title.uppercased())
            }
        }
    }

    /// Tracked-caps Liquid section header.
    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .tracking(0.8)
            .foregroundStyle(DS.ColorToken.textTertiary)
    }

    @ViewBuilder
    func row(for item: TaskItem, appearIndex: Int? = nil) -> some View {
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

    /// Row tap: toggles selection while in multi-select mode (the `.selectable`
    /// checkmark is presentation-only and can't capture taps inside a List),
    /// otherwise opens the task.
    func handleRowTap(_ item: TaskItem) {
        if selection.isSelecting {
            withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
        } else {
            onSelect?(item)
        }
    }

    /// Project name for the row pill, or nil to suppress it. Suppressed for
    /// Inbox tasks (no project) and when the list is already sectioned by
    /// project (the section header carries that context).
    func resolvedProjectName(for item: TaskItem) -> String? {
        guard groupBy.wrappedValue != .project else { return nil }
        guard let projectID = item.projectID else { return nil }
        return projectsByID[projectID]?.name
    }

    func rowView(for item: TaskItem) -> some View {
        TaskRowView(
            task: item,
            projectName: resolvedProjectName(for: item),
            now: now,
            subtaskProgress: subtaskProgressByTaskID[item.id],
            isSubtasksExpanded: expandedTaskIDs.contains(item.id),
            showsDefaultTaskAssistMenu: false,
            onToggleSubtasks: { toggleExpansion(for: item) },
            onToggleDone: { toggleDone(item) },
            onSnooze: { snooze(item, by: .oneHour) },
            isSelecting: selection.isSelecting,
            isSelected: selection.isSelected(id: item.id)
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(containerBackground)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { handleRowTap(item) }
        #if os(iOS)
        .onLongPressGesture {
            withAnimation(DS.Motion.selection) {
                selection.enterSelection()
                selection.toggle(id: item.id)
            }
        }
        #endif
        .swipeActions(edge: .leading) { leadingSwipeActions(for: item) }
        .swipeActions(edge: .trailing) { trailingSwipeActions(for: item) }
        .taskAssistContextMenu(for: item) { actions in
            if item.isTemplate {
                Button("New Task from Template") { instantiateTemplate(item) }
                // I-D1: no complete/snooze/subtask affordances on an inert blueprint.
                Button("Delete Template", role: .destructive) { deleteTemplate(item) }
            } else {
                Button(item.status == .done ? "Reopen" : "Mark done") { toggleDone(item) }
                Button(item.pinnedAsFocus ? "Unpin from Today" : "Pin to Today") { togglePin(item) }
                Divider()
                Button("Duplicate") { duplicate(item) }
                Menu("Set Priority") {
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { p in
                        Button(TaskListView.priorityLabel(p)) { setPriority(p, for: item) }
                    }
                }
                Button("Move to Project…") {
                    contextMoveActiveProjects = loadActiveProjects()
                    contextMoveTarget = item
                }
                Divider()
                Button("Copy as Markdown") { copyAsMarkdown(item) }
                Button("Copy Link") { copyLink(item) }
                // "Convert to Note": cross-module — requires app-shell to expose a
                // `convertTaskToNote` closure via environment so the result can be
                // navigated to. Seam: not implemented in this pass.
                Divider()
                Button("Save as Template") { saveAsTemplate(item) }
                Button("Subtask of…") { parentPickerTarget = item }
                Button("Snooze 1h") { snooze(item, by: .oneHour) }
                Button("Snooze until tomorrow") { snooze(item, by: .tomorrow) }
                TaskAssistMenuSection(actions: actions)
            }
        }
        // Re-assert separator-hidden at the OUTERMOST level: the `.selectable`
        // HStack wrap breaks the inner `.listRowSeparator(.hidden)` propagation,
        // so the `.inset` list re-shows its default separator on top of
        // TaskRowView's own hairline (the "double line").
        .listRowSeparator(.hidden)
    }
}
