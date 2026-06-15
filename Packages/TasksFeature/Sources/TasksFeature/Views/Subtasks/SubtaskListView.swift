import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct SubtaskProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    public var isComplete: Bool {
        total > 0 && done == total
    }

    public var label: String {
        "\(done)/\(total)"
    }
}

@MainActor
enum SubtaskTreeDataSource {
    static func activeChildren(of parent: TaskItem, modelContext: ModelContext) throws -> [TaskItem] {
        try activeChildren(parentID: parent.id, modelContext: modelContext)
    }

    static func activeChildren(parentID: UUID, modelContext: ModelContext) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.parentTaskID == parentID && task.deletedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).sorted(by: assignmentOrder)
    }

    static func progress(parentID: UUID, modelContext: ModelContext) throws -> SubtaskProgress? {
        let children = try activeChildren(parentID: parentID, modelContext: modelContext)
        guard !children.isEmpty else { return nil }
        return SubtaskProgress(
            done: children.filter { $0.status == .done }.count,
            total: children.count
        )
    }

    static func progress(
        for parents: [TaskItem],
        modelContext: ModelContext
    ) throws -> [UUID: SubtaskProgress] {
        let parentIDs = Set(parents.map(\.id))
        guard !parentIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                if let parentTaskID = task.parentTaskID {
                    task.deletedAt == nil && parentIDs.contains(parentTaskID)
                } else {
                    false
                }
            }
        )
        let groupedChildren = Dictionary(grouping: try modelContext.fetch(descriptor)) { task in
            task.parentTaskID
        }
        return parentIDs.reduce(into: [:]) { result, parentID in
            let children = groupedChildren[Optional(parentID), default: []]
            guard !children.isEmpty else { return }
            result[parentID] = SubtaskProgress(
                done: children.filter { $0.status == .done }.count,
                total: children.count
            )
        }
    }

    static func rootTasks(from tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { $0.parentTaskID == nil }
    }

    private static func assignmentOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
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
}

public struct SubtaskListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    @Bindable public var parent: TaskItem
    public let now: Date
    public let depth: Int
    @Binding public var expandedTaskIDs: Set<UUID>
    public let onSelect: ((TaskItem) -> Void)?

    @State private var children: [TaskItem] = []
    @State private var progressByTaskID: [UUID: SubtaskProgress] = [:]
    @State private var parentPickerTarget: TaskItem?
    @State private var cascadePrompt: CascadeCompletionPrompt?
    @State private var error: String?

    /// Hard ceiling on rendered subtask depth. The current product scope keeps
    /// subtasks at one level; the cap leaves a little headroom for the parent
    /// picker rework and protects against accidental infinite recursion if a
    /// data cycle ever lands.
    private static let maxRenderDepth = 3

    public init(
        parent: TaskItem,
        now: Date = .now,
        depth: Int = 1,
        expandedTaskIDs: Binding<Set<UUID>>,
        onSelect: ((TaskItem) -> Void)? = nil
    ) {
        self._parent = Bindable(parent)
        self.now = now
        self.depth = depth
        self._expandedTaskIDs = expandedTaskIDs
        self.onSelect = onSelect
    }

    public var body: some View {
        if depth >= Self.maxRenderDepth {
            EmptyView()
        } else {
            content
        }
    }

    /// Mirrors `TaskListView.containerBackground`: transparent on macOS so
    /// subtask rows sit on the shell's glass panel; iOS keeps the opaque base
    /// under its own (still Linear) shell.
    private var rowContainerBackground: Color {
        #if os(macOS)
        return Color.clear
        #else
        return NexusColor.Background.base
        #endif
    }

    @ViewBuilder
    private var content: some View {
        Group {
            ForEach(children) { child in
                row(for: child)
            }
            if let error {
                Text(error)
                    .font(DS.FontToken.metadata)
                    // Error legibility is carried by contrast/weight, not color.
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .padding(.leading, CGFloat(min(depth, 6)) * 20 + 18)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(rowContainerBackground)
                    .listRowSeparator(.hidden)
            }
        }
        .task(id: parent.id) { reload() }
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

    @ViewBuilder
    private func row(for item: TaskItem) -> some View {
        TaskRowView(
            task: item,
            now: now,
            depth: depth,
            subtaskProgress: progressByTaskID[item.id],
            isSubtasksExpanded: expandedTaskIDs.contains(item.id),
            showsDefaultTaskAssistMenu: false,
            onToggleSubtasks: { toggleExpansion(for: item) },
            onToggleDone: { toggleDone(item) }
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(rowContainerBackground)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(item) }
        .swipeActions(edge: .leading) {
            Button {
                toggleDone(item)
            } label: {
                Label(item.status == .done ? "Reopen" : "Done", systemImage: "checkmark.circle")
            }
            // Solid dark swipe fill so the white system label stays legible.
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
            Button(item.status == .done ? "Reopen" : "Mark done") { toggleDone(item) }
            Button("Subtask of…") { parentPickerTarget = item }
            Button("Snooze 1h") { snooze(item, by: .oneHour) }
            Button("Snooze until tomorrow") { snooze(item, by: .tomorrow) }
            TaskAssistMenuSection(actions: actions)
        }

        if expandedTaskIDs.contains(item.id) {
            SubtaskListView(
                parent: item,
                now: now,
                depth: depth + 1,
                expandedTaskIDs: $expandedTaskIDs,
                onSelect: onSelect
            )
        }
    }

    @MainActor
    private func reload() {
        do {
            children = try SubtaskTreeDataSource.activeChildren(of: parent, modelContext: modelContext)
            progressByTaskID = try SubtaskTreeDataSource.progress(
                for: children,
                modelContext: modelContext
            )
            error = nil
        } catch {
            self.error = String(describing: error)
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
            // Animate the row leaving the list on completion (see TaskListView).
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
