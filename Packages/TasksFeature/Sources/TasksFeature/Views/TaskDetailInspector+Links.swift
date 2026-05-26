import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

struct TaskParentPickerState {
    var parent: TaskItem?
    var searchText: String = ""
    var candidates: [TaskItem] = []
}

struct ParentTaskPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    @Bindable var task: TaskItem
    let onAssigned: () -> Void

    @State private var searchText = ""
    @State private var candidates: [TaskItem] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Subtask of…")
                    .nexusType(.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            TextField("Find parent task", text: $searchText)
                .onChange(of: searchText) { _, _ in reload() }

            if let error {
                Text(error)
                    .font(.caption)
                    // MP-2 burned: error text renders via primary ink
                    .foregroundStyle(NexusColor.Text.primary)
            } else if candidates.isEmpty {
                Text("No eligible root tasks in this project.")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates, id: \.id) { candidate in
                        Button {
                            assign(to: candidate)
                        } label: {
                            HStack {
                                Text(candidate.title)
                                    .foregroundStyle(NexusColor.Text.primary)
                                Spacer()
                                Image(systemName: "arrow.turn.down.right")
                                    // MP-2 burned: decorative affordance glyph → tertiary ink
                                    .foregroundStyle(NexusColor.Text.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 220, alignment: .topLeading)
        .background(NexusColor.Background.base)
        .task { reload() }
    }

    @MainActor
    private func reload() {
        do {
            candidates = try TaskParentPickerDataSource.candidates(
                for: task,
                query: searchText,
                modelContext: modelContext
            )
            error = nil
        } catch {
            candidates = []
            self.error = "Couldn't load parent tasks."
        }
    }

    @MainActor
    private func assign(to parent: TaskItem) {
        guard let repository else {
            error = "Couldn't assign parent task."
            return
        }
        do {
            if try TaskParentPickerDataSource.assign(
                task: task,
                toParent: parent,
                repository: repository,
                modelContext: modelContext
            ) {
                onAssigned()
                dismiss()
            } else {
                reload()
            }
        } catch {
            self.error = "Couldn't assign parent task."
        }
    }
}

@MainActor
enum TaskParentPickerDataSource {
    static func candidates(
        for task: TaskItem,
        query: String,
        modelContext: ModelContext
    ) throws -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { candidate in
                candidate.deletedAt == nil && candidate.parentTaskID == nil
            },
            sortBy: [SortDescriptor(\TaskItem.title, order: .forward)]
        )
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidates: [TaskItem] = []
        for candidate in try modelContext.fetch(descriptor) {
            guard try canAssign(task, toParent: candidate, modelContext: modelContext) else { continue }
            guard trimmedQuery.isEmpty || candidate.title.lowercased().contains(trimmedQuery) else {
                continue
            }
            candidates.append(candidate)
            if candidates.count == 8 { break }
        }
        return candidates
    }

    static func assign(
        task: TaskItem,
        toParent parent: TaskItem,
        repository: TaskItemRepository,
        modelContext: ModelContext
    ) throws -> Bool {
        guard try canAssign(task, toParent: parent, modelContext: modelContext) else { return false }
        try repository.update(task) { item in
            item.parentTaskID = parent.id
            item.projectID = parent.projectID
            item.sectionID = parent.sectionID
        }
        return true
    }

    static func canAssign(
        _ task: TaskItem,
        toParent parent: TaskItem,
        modelContext: ModelContext
    ) throws -> Bool {
        guard task.id != parent.id else { return false }
        guard task.parentTaskID != parent.id else { return false }
        guard parent.deletedAt == nil else { return false }
        guard parent.status == .open else { return false }
        guard parent.parentTaskID == nil else { return false }
        guard parent.projectID == task.projectID else { return false }
        guard try activeDirectChildCount(parentID: task.id, modelContext: modelContext) == 0 else {
            return false
        }
        return try !wouldCreateParentCycle(task: task, parent: parent, modelContext: modelContext)
    }

    private static func activeDirectChildCount(parentID: UUID, modelContext: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { candidate in
                candidate.parentTaskID == parentID && candidate.deletedAt == nil
            }
        )
        return try modelContext.fetchCount(descriptor)
    }

    private static func wouldCreateParentCycle(
        task: TaskItem,
        parent: TaskItem,
        modelContext: ModelContext
    ) throws -> Bool {
        var seen = Set<UUID>()
        var currentID = parent.parentTaskID
        while let id = currentID {
            if id == task.id { return true }
            guard seen.insert(id).inserted else { return true }
            currentID = try fetchTask(id: id, modelContext: modelContext)?.parentTaskID
        }
        return false
    }

    private static func fetchTask(id: UUID, modelContext: ModelContext) throws -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { candidate in
                candidate.id == id && candidate.deletedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}

extension TaskDetailInspector {
    var linksCard: some View {
        inspectorCard("Links") {
            parentTaskSection
            newSubtaskSection

            VStack(alignment: .leading, spacing: 10) {
                Text("Blocks")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                outgoingBlocksList
                blockSearchField
            }

            if !incomingBlockerTasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blocked by")
                        .nexusType(.caption)
                        // MP-2 burned: emphasis label → primary ink (state conveyed by copy)
                        .foregroundStyle(NexusColor.Text.primary)
                    blockedByList
                }
            }
        }
    }

    var newSubtaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subtasks")
                .nexusType(.caption)
                .foregroundStyle(NexusColor.Text.muted)

            Button {
                createNewSubtask()
            } label: {
                Label("New subtask", systemImage: "plus")
            }
            .buttonStyle(.plain)
            // MP-2 burned: decorative action affordance → tertiary ink
            .foregroundStyle(NexusColor.Text.tertiary)

            if let subtaskActionError {
                Text(subtaskActionError)
                    .font(.caption)
                    // MP-2 burned: error text renders via primary ink
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }

    var parentTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parent task")
                .nexusType(.caption)
                .foregroundStyle(NexusColor.Text.muted)

            if let parentTask = parentTaskPicker.parent {
                NexusChip(
                    parentTask.title,
                    systemImage: "arrow.turn.down.right",
                    tone: .accent,
                    onRemove: clearParentTask
                )
            } else {
                Text("Root task")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            TextField("Make subtask of…", text: $parentTaskPicker.searchText)
                .onChange(of: parentTaskPicker.searchText) { _, _ in refreshParentCandidates() }

            if !parentTaskPicker.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(parentTaskPicker.candidates, id: \.id) { candidate in
                        Button {
                            assignParentTask(candidate)
                        } label: {
                            HStack {
                                Text(candidate.title)
                                    .foregroundStyle(NexusColor.Text.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    // MP-2 burned: decorative affordance glyph → tertiary ink
                                    .foregroundStyle(NexusColor.Text.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set parent task: \(candidate.title)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    var outgoingBlocksList: some View {
        if outgoingBlockedTasks.isEmpty {
            Text("Doesn't block anything yet")
                .font(.caption)
                .foregroundStyle(NexusColor.Text.tertiary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(outgoingBlockedTasks, id: \.id) { target in
                        NexusChip(
                            target.title,
                            tone: .accent,
                            onRemove: { removeBlock(targetID: target.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    var blockedByList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(incomingBlockerTasks, id: \.id) { blocker in
                    NexusChip(blocker.title, tone: .rose)
                }
            }
            .padding(.vertical, 2)
        }
    }

    var blockSearchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Block another task…", text: $blockSearchText)
                .onChange(of: blockSearchText) { _, _ in refreshBlockCandidates() }
            if !blockSearchCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(blockSearchCandidates, id: \.id) { candidate in
                        Button {
                            addBlock(target: candidate)
                        } label: {
                            HStack {
                                Text(candidate.title)
                                    .foregroundStyle(NexusColor.Text.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    // MP-2 burned: decorative affordance glyph → tertiary ink
                                    .foregroundStyle(NexusColor.Text.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add block: \(candidate.title)")
                    }
                }
            }
        }
    }

    @MainActor
    func loadLinkState() {
        loadBlocks()
        loadParentTask()
    }

    @MainActor
    func loadParentTask() {
        do {
            parentTaskPicker.parent = try task.parentTaskID.flatMap { try fetchTask(id: $0) }
            refreshParentCandidates()
        } catch {
            parentTaskPicker.parent = nil
            parentTaskPicker.candidates = []
        }
    }

    @MainActor
    func refreshParentCandidates() {
        do {
            parentTaskPicker.candidates = try TaskParentPickerDataSource.candidates(
                for: task,
                query: parentTaskPicker.searchText,
                modelContext: modelContext
            )
        } catch {
            parentTaskPicker.candidates = []
        }
    }

    @MainActor
    func assignParentTask(_ parent: TaskItem) {
        guard let repository else { return }
        do {
            if try TaskParentPickerDataSource.assign(
                task: task,
                toParent: parent,
                repository: repository,
                modelContext: modelContext
            ) {
                parentTaskPicker.parent = parent
                parentTaskPicker.searchText = ""
            }
            refreshParentCandidates()
        } catch {
            refreshParentCandidates()
        }
    }

    @MainActor
    func clearParentTask() {
        guard let repository else { return }
        do {
            try repository.update(task) { item in
                item.parentTaskID = nil
            }
            parentTaskPicker.parent = nil
            refreshParentCandidates()
        } catch {
            refreshParentCandidates()
        }
    }

    @MainActor
    func fetchTask(id: UUID) throws -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { candidate in
                candidate.id == id && candidate.deletedAt == nil
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    @MainActor
    func createNewSubtask() {
        guard let repository else {
            subtaskActionError = "Couldn't create subtask."
            return
        }
        do {
            _ = try TaskSubtaskAction.createChild(under: task, repository: repository)
            subtaskActionError = nil
        } catch let actionError as TaskSubtaskActionError {
            subtaskActionError = actionError.localizedDescription
        } catch {
            subtaskActionError = "Couldn't create subtask."
        }
    }

    @MainActor
    func loadBlocks() {
        let linkRepository = LinkRepository(context: modelContext)
        do {
            let outgoing =
                try linkRepository
                .outgoingBlocks(from: (.task, task.id))
                .filter { $0.toKind == .task }
            let incoming =
                try linkRepository
                .incomingBlocks(to: (.task, task.id))
                .filter { $0.fromKind == .task }
            outgoingBlockedTasks = try fetchTasks(ids: outgoing.map(\.toID))
            incomingBlockerTasks = try fetchTasks(ids: incoming.map(\.fromID))
            refreshBlockCandidates()
        } catch {
            outgoingBlockedTasks = []
            incomingBlockerTasks = []
            blockSearchCandidates = []
        }
    }

    @MainActor
    func fetchTasks(ids: [UUID]) throws -> [TaskItem] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\TaskItem.title, order: .forward)]
        )
        let tasks = try modelContext.fetch(descriptor)
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        return ids.compactMap { taskByID[$0] }
    }

    @MainActor
    func refreshBlockCandidates() {
        do {
            let openStatus = TaskStatus.open.rawValue
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { candidate in
                    candidate.deletedAt == nil && candidate.statusRaw == openStatus
                },
                sortBy: [SortDescriptor(\TaskItem.title, order: .forward)]
            )
            let trimmedQuery =
                blockSearchText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let alreadyLinked = Set(outgoingBlockedTasks.map(\.id))
            blockSearchCandidates = try modelContext.fetch(descriptor)
                .filter { candidate in
                    candidate.id != task.id
                        && !alreadyLinked.contains(candidate.id)
                        && (trimmedQuery.isEmpty
                            || candidate.title.lowercased().contains(trimmedQuery))
                }
                .prefix(8)
                .map { $0 }
        } catch {
            blockSearchCandidates = []
        }
    }

    @MainActor
    func addBlock(target: TaskItem) {
        let linkRepository = LinkRepository(context: modelContext)
        let actions = TaskDetailInspectorBlocksActions(task: task, linkRepository: linkRepository)
        do {
            try actions.addBlock(target: target)
            blockSearchText = ""
            loadBlocks()
        } catch {
            refreshBlockCandidates()
        }
    }

    @MainActor
    func removeBlock(targetID: UUID) {
        let linkRepository = LinkRepository(context: modelContext)
        let actions = TaskDetailInspectorBlocksActions(task: task, linkRepository: linkRepository)
        do {
            try actions.removeBlock(targetID: targetID)
            loadBlocks()
        } catch {
            refreshBlockCandidates()
        }
    }
}
