import NexusCore
import NexusUI
import SwiftUI

/// Fixed trailing-column widths so rows align like a table without `Table`'s
/// chrome (spec §All Tasks table; the Task column takes the remaining width).
private let statusColumnWidth: CGFloat = 92
private let priorityColumnWidth: CGFloat = 72
private let dueColumnWidth: CGFloat = 64
private let sectionColumnWidth: CGFloat = 110
/// Table row height — spec §Visual rules allows this module to run denser
/// than Today; 36 pt matches the reference's compact table rows.
private let tableRowHeight: CGFloat = 36

/// Priority filter chips (spec §All Tasks table filters). "Blocked" is
/// intentionally absent — the workflow machine has no blocked state.
enum ProjectTaskPriorityFilter: String, CaseIterable, Identifiable {
    case all
    case high
    case medium
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    func matches(_ task: TaskItem) -> Bool {
        switch self {
        case .all: return true
        case .high: return task.priority == .high
        case .medium: return task.priority == .medium
        case .low: return task.priority == .low
        }
    }
}

/// All Tasks table (spec §All Tasks table): real filters (priority chips,
/// workflow-status menu, live search) over the selected project's tasks;
/// columns Task / Status / Priority / Due / Section. No Assignee column
/// (single-user app) and no Sprint column (no sprint backend). Header-click
/// sorting skipped (nice-to-have; rows keep the board's `orderIndex` order).
struct ProjectTaskTable: View {

    let tasks: [TaskItem]
    let sectionNames: [UUID: String]
    let now: Date
    let onSelect: (TaskItem) -> Void

    @State private var priorityFilter: ProjectTaskPriorityFilter = .all
    /// `.some(nil)` = the "No Status" lane; `nil` = any status.
    @State private var statusFilter: WorkflowState?? = WorkflowState??.none
    @State private var searchText = ""

    private var filteredTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { task in
            guard priorityFilter.matches(task) else { return false }
            if let statusFilter, task.workflowState != statusFilter { return false }
            if !query.isEmpty, !task.title.lowercased().contains(query) { return false }
            return true
        }
    }

    var body: some View {
        LiquidGlassCard("All Tasks") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                filterBar

                if tasks.isEmpty {
                    LiquidEmptyState(
                        systemImage: "checklist",
                        message: "No tasks in this project yet. Add one from the board."
                    )
                } else if filteredTasks.isEmpty {
                    LiquidEmptyState(
                        systemImage: "line.3.horizontal.decrease",
                        message: "No tasks match the current filters."
                    )
                } else {
                    headerRow
                    LiquidDividerLine()
                    ForEach(filteredTasks) { task in
                        TaskTableRow(
                            task: task,
                            sectionName: task.sectionID.flatMap { sectionNames[$0] },
                            now: now,
                            onSelect: onSelect
                        )
                    }
                }
            }
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: DS.Space.s) {
            LiquidSegmentedControl(
                options: ProjectTaskPriorityFilter.allCases.map { .init($0, label: $0.label) },
                selection: $priorityFilter
            )

            statusMenu

            Spacer(minLength: DS.Space.s)

            searchField
        }
    }

    private var statusMenu: some View {
        Menu {
            Button {
                statusFilter = WorkflowState??.none
            } label: {
                menuItemLabel("Any Status", isSelected: statusFilter == WorkflowState??.none)
            }
            ForEach(projectBoardPrimaryStates, id: \.self) { state in
                Button {
                    statusFilter = .some(state)
                } label: {
                    menuItemLabel(
                        ProjectBoardColumn.title(for: state),
                        isSelected: statusFilter == .some(state)
                    )
                }
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(statusFilterLabel)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Image(systemName: "chevron.down")
                    // 8 pt chevron rides the 13 pt body baseline; no DS icon token.
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            .padding(.horizontal, DS.Space.m)
            .frame(height: 28)
            .background {
                Capsule(style: .continuous).fill(DS.ColorToken.glassSoft)
            }
            .overlay {
                Capsule(style: .continuous).stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Filter by status: \(statusFilterLabel)")
    }

    @ViewBuilder
    private func menuItemLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var statusFilterLabel: String {
        guard let statusFilter else { return "Any Status" }
        return ProjectBoardColumn.title(for: statusFilter)
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                // 11 pt magnifier matches the metadata placeholder scale.
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(width: 180, height: 28)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(DS.ColorToken.glassSoft)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: DS.Space.s) {
            columnLabel("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            columnLabel("Status")
                .frame(width: statusColumnWidth, alignment: .leading)
            columnLabel("Priority")
                .frame(width: priorityColumnWidth, alignment: .leading)
            columnLabel("Due")
                .frame(width: dueColumnWidth, alignment: .leading)
            columnLabel("Section")
                .frame(width: sectionColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.s)
        .accessibilityHidden(true)
    }

    private func columnLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textMuted)
    }
}

// MARK: - Row

private struct TaskTableRow: View {
    let task: TaskItem
    let sectionName: String?
    let now: Date
    let onSelect: (TaskItem) -> Void

    @State private var hovering = false

    /// Lane accent shared with the Kanban headers (one status → one color).
    private var statusColor: Color {
        switch task.workflowState {
        case .todo: return DS.ColorToken.accentBlue
        case .inProgress: return DS.ColorToken.accentAmber
        case .inReview: return DS.ColorToken.accentPurple
        case .done: return DS.ColorToken.accentGreen
        case nil, .backlog, .canceled, .duplicate: return DS.ColorToken.statusNeutral
        }
    }

    private var isOverdue: Bool {
        guard let due = task.dueAt else { return false }
        return due < now && task.status != .done
    }

    var body: some View {
        Button {
            onSelect(task)
        } label: {
            HStack(spacing: DS.Space.s) {
                Text(task.title)
                    .font(DS.FontToken.body)
                    .strikethrough(task.status == .done)
                    .foregroundStyle(
                        task.status == .done ? DS.ColorToken.textTertiary : DS.ColorToken.textPrimary
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LiquidPill(ProjectBoardColumn.title(for: task.workflowState), color: statusColor)
                    .frame(width: statusColumnWidth, alignment: .leading)

                Group {
                    if task.priority == .none {
                        dashPlaceholder
                    } else {
                        LiquidPill(
                            TopPrioritiesCard.label(for: task.priority),
                            color: TopPrioritiesCard.color(for: task.priority)
                        )
                    }
                }
                .frame(width: priorityColumnWidth, alignment: .leading)

                Group {
                    if let due = task.dueAt {
                        Text(Self.dueFormatter.string(from: due))
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(
                                isOverdue ? DS.ColorToken.statusDanger : DS.ColorToken.textSecondary
                            )
                    } else {
                        dashPlaceholder
                    }
                }
                .frame(width: dueColumnWidth, alignment: .leading)

                Group {
                    if let sectionName {
                        Text(sectionName)
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .lineLimit(1)
                    } else {
                        dashPlaceholder
                    }
                }
                .frame(width: sectionColumnWidth, alignment: .leading)
            }
            .padding(.horizontal, DS.Space.s)
            .frame(minHeight: tableRowHeight)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    // Same 4% hover wash as LiquidTaskRow (09_IMPLEMENTATION §Hover:
                    // no scale in dense lists).
                    .fill(hovering ? Color.white.opacity(0.04) : .clear)
            }
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
        .accessibilityLabel(task.title)
    }

    private var dashPlaceholder: some View {
        Text("—")
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textMuted)
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
