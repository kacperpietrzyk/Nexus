import NexusCore
import NexusUI
import SwiftData
import SwiftUI

// MARK: - Bulk action helpers and enriched context-menu items for TaskListView.
//
// Split from TaskListView.swift to keep that file under the type-body budget.
// All methods are `@MainActor` — same isolation as the view body and the
// repository calls they delegate to.

extension TaskListView {

    // MARK: - Bulk: complete

    @MainActor
    func bulkComplete() {
        guard let repository else { return }
        let ids = selection.selectedIDs
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            guard task.status != TaskStatus.done else { continue }
            try? TaskCompletionAction.complete(task, repository: repository)
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    // MARK: - Bulk: snooze

    @MainActor
    func bulkSnooze(by offset: BulkSnoozeOffset) {
        guard let repository else { return }
        let ids = selection.selectedIDs
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let until = Self.snoozeDate(for: offset, from: now, calendar: cal)
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            try? repository.snooze(task, until: until)
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    enum BulkSnoozeOffset { case oneHour, tomorrow }

    /// Pure snooze-target computation — isolated from SwiftData so it is unit-testable.
    static func snoozeDate(for offset: BulkSnoozeOffset, from now: Date, calendar: Calendar = .current) -> Date {
        switch offset {
        case .oneHour:
            return now.addingTimeInterval(3_600)
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        }
    }

    // MARK: - Bulk: set priority

    @MainActor
    func bulkSetPriority(_ priority: TaskPriority) {
        guard let repository else { return }
        let ids = selection.selectedIDs
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            try? repository.update(task) { $0.priorityRaw = priority.rawValue }
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    // MARK: - Bulk: pin to Today

    @MainActor
    func bulkPin() {
        guard let repository else { return }
        let ids = selection.selectedIDs
        // If any selected is un-pinned, pin all; otherwise unpin all.
        let anyUnpinned = ids.contains { id in
            visibleRootTasks.first(where: { $0.id == id })?.pinnedAsFocus == false
        }
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            let target = anyUnpinned ? true : false
            if task.pinnedAsFocus != target {
                try? repository.update(task) { $0.pinnedAsFocus = target }
            }
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    // MARK: - Bulk: move to project

    @MainActor
    func bulkMove(toProject projectID: UUID?) {
        guard let repository else { return }
        let ids = selection.selectedIDs
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            try? repository.assign(task, toProject: projectID)
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    // MARK: - Bulk: delete with undo

    @MainActor
    func bulkDelete() {
        guard let repository else { return }
        let ids = selection.selectedIDs
        let count = ids.count
        // Collect the live TaskItem objects BEFORE soft-deleting. Because
        // UndoController's closure is @MainActor (same actor as this method and
        // the SwiftData context), we can capture the @Model references directly
        // and restore them by clearing deletedAt — no duplicate-row risk.
        var tasks: [TaskItem] = []
        for id in ids {
            guard let task = visibleRootTasks.first(where: { $0.id == id }) else { continue }
            tasks.append(task)
        }
        for task in tasks {
            try? repository.softDelete(task, cascade: false)
        }
        let ctx = modelContext
        undo.show(
            message: count == 1 ? "Deleted 1 task" : "Deleted \(count) tasks",
            icon: "trash"
        ) { [self] in
            let stamp = Date.now
            for task in tasks {
                task.deletedAt = nil
                task.updatedAt = stamp
            }
            try? ctx.save()
            reload()
        }
        withAnimation(DS.Motion.standard) {
            selection.exitSelection()
            reload()
        }
    }

    // MARK: - Per-row context: duplicate

    @MainActor
    func duplicate(_ item: TaskItem) {
        guard let repository else { return }
        let copy = TaskItem(
            title: item.title,
            dueAt: item.dueAt,
            deadlineAt: item.deadlineAt,
            priority: item.priority,
            tags: item.tags,
            parentTaskID: item.parentTaskID,
            projectID: item.projectID,
            sectionID: item.sectionID
        )
        do {
            try repository.insert(copy)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Per-row context: set priority (single task)

    @MainActor
    func setPriority(_ priority: TaskPriority, for item: TaskItem) {
        guard let repository else { return }
        do {
            try repository.update(item) { $0.priorityRaw = priority.rawValue }
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Per-row context: move to project (single task)

    @MainActor
    func moveToProject(_ projectID: UUID?, for item: TaskItem) {
        guard let repository else { return }
        do {
            try repository.assign(item, toProject: projectID)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Per-row context: pin/unpin

    @MainActor
    func togglePin(_ item: TaskItem) {
        guard let repository else { return }
        do {
            try repository.update(item) { $0.pinnedAsFocus.toggle() }
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Per-row context: copy as Markdown

    func copyAsMarkdown(_ item: TaskItem) {
        let metadata = Self.markdownMetadata(for: item, dateFormatter: Self.copyDateFormatter)
        let md = MarkdownExport.entity(title: item.title, metadata: metadata)
        PasteboardCopy.string(md)
    }

    /// Pure metadata-line builder — isolated from the pasteboard so it's unit-testable.
    static func markdownMetadata(for item: TaskItem, dateFormatter: DateFormatter) -> [String] {
        var metadata: [String] = []
        if item.priority != .none {
            metadata.append("Priority: \(Self.priorityLabel(item.priority))")
        }
        if let due = item.dueAt {
            metadata.append("Due: \(dateFormatter.string(from: due))")
        }
        if !item.tags.isEmpty {
            metadata.append("Tags: \(item.tags.joined(separator: ", "))")
        }
        return metadata
    }

    // MARK: - Per-row context: copy link

    func copyLink(_ item: TaskItem) {
        PasteboardCopy.string("nexus://task/\(item.id.uuidString)")
    }

    // MARK: - Bulk: copy as Markdown (multi-select)

    func bulkCopyAsMarkdown() {
        let ids = selection.selectedIDs
        let items = visibleRootTasks.filter { ids.contains($0.id) }
        let blocks = items.map { item -> String in
            let metadata = Self.markdownMetadata(for: item, dateFormatter: Self.copyDateFormatter)
            return MarkdownExport.entity(title: item.title, metadata: metadata)
        }
        PasteboardCopy.string(MarkdownExport.list(blocks))
        withAnimation(DS.Motion.standard) { selection.exitSelection() }
    }

    static func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .none: return "None"
        }
    }

    private static let copyDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    // MARK: - Active projects for bulk/context-menu pickers

    @MainActor
    func loadActiveProjects() -> [Project] {
        (try? ProjectRepository(context: modelContext).allActive()) ?? []
    }
}
