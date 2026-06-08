import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Card-based editor for a single task. Auto-saves on field commit; recurrence
/// picker emits curated RRULE strings ("Custom" surfaces a direct-edit field).
public struct TaskDetailInspector: View {

    @Environment(\.modelContext) var modelContext
    @Environment(\.taskRepository) var repository

    /// Field arrangement. `.column` is the single-column scroll (iOS sheet /
    /// pushed view — the default). `.wide` is a 2-column, content-hugging layout
    /// for the Mac centered modal, so the dialog is short and needs little/no
    /// scrolling instead of a tall single-column stack.
    public enum Layout { case column, wide }

    typealias RecurrenceChoice = TaskDetailRecurrenceChoice

    @Bindable public var task: TaskItem
    public let onClose: (() -> Void)?
    public let layout: Layout

    @State private var allDay: Bool
    @State private var recurrenceChoice: RecurrenceChoice
    @State private var customRRule: String
    @State private var saveTask: _Concurrency.Task<Void, Never>?
    @State private var notesDraft: String
    @State private var notesSaveTask: _Concurrency.Task<Void, Never>?
    @State var outgoingBlockedTasks: [TaskItem] = []
    @State var incomingBlockerTasks: [TaskItem] = []
    @State var blockSearchText: String = ""
    @State var blockSearchCandidates: [TaskItem] = []
    @State var parentTaskPicker = TaskParentPickerState()
    @State var subtaskActionError: String?
    @State var parentPickerPresented = false
    @State var blockPickerPresented = false
    @State var assignedLabels: [TaskLabel] = []
    @State var availableLabels: [TaskLabel] = []
    @State var newLabelDraft: String = ""
    @State var promoteConfirmation = false
    @State var promoteError: String?

    public init(task: TaskItem, onClose: (() -> Void)? = nil, layout: Layout = .column) {
        self._task = Bindable(task)
        self.onClose = onClose
        self.layout = layout
        self._allDay = State(initialValue: task.startAt == nil)
        self._recurrenceChoice = State(
            initialValue: RecurrenceChoice.from(rrule: task.recurrenceRule)
        )
        self._customRRule = State(initialValue: task.recurrenceRule ?? "")
        self._notesDraft = State(initialValue: task.body)
    }

    /// Re-derives the editor's `@State` from the current `task`. Mirrors the
    /// `init` derivations; called when the bound task identity changes while
    /// the view is reused, so the controls reflect the new task instead of the
    /// previous one.
    private func resyncDerivedState() {
        allDay = task.startAt == nil
        recurrenceChoice = RecurrenceChoice.from(rrule: task.recurrenceRule)
        customRRule = task.recurrenceRule ?? ""
    }

    public var body: some View {
        layoutBody
            .background(NexusColor.Background.base)
            // This panel hosts in a detached overlay (Mac modal) / sheet that does
            // NOT inherit the app-root `.tint`, so its native controls (segmented
            // Priority picker, toggles, DatePickers) would fall back to system blue.
            // Re-assert the achromatic control tint here (lime stays for actions).
            .tint(NexusColor.Text.primary)
            .navigationTitle(task.title.isEmpty ? "Task" : task.title)
            .task {
                loadLinkState()
                loadNotesDraft()
            }
            .onChange(of: task.id) { _, _ in
                // View identity is reused across selection swaps; resync derived
                // state else an edit writes the previous task's fields onto the new.
                resyncDerivedState()
                loadLinkState()
                loadNotesDraft()
            }
            .onKeyPress(.escape) {
                onClose?()
                return onClose == nil ? .ignored : .handled
            }
    }

    var headerCard: some View {
        inspectorCard("Task") {
            HStack(alignment: .top, spacing: 8) {
                TextField("Title", text: $task.title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(NexusType.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1...3)
                    .onChange(of: task.title) { _, _ in saveDebounced() }
                    .onSubmit { save() }

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .background(
                        NexusColor.Background.control.opacity(0.6),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(NexusColor.Line.hairline, lineWidth: 1)
                    )
                    .accessibilityLabel("Close inspector")
                    .keyboardShortcut(.cancelAction)
                }
            }

            HStack(spacing: 8) {
                priorityStatusChip
                lifecycleChip
                if let dueChipLabel {
                    // Lime economy: future due = neutral; only OVERDUE is loud (`.rose`).
                    NexusChip(
                        dueChipLabel,
                        systemImage: isOverdue ? "exclamationmark.triangle.fill" : "calendar",
                        tone: isOverdue ? .rose : .neutral
                    )
                }
                Spacer(minLength: 0)
            }

            priorityPicker

            Toggle("Pin as focus", isOn: $task.pinnedAsFocus)
                .onChange(of: task.pinnedAsFocus) { _, _ in save() }

            TagsEditor(tags: $task.tags) { save() }
        }
    }

    var aiAssistCard: some View {
        inspectorCard("AI Assist") {
            TaskAssistButtonGroup(task: task)
        }
    }

    var scheduleCard: some View {
        inspectorCard("Schedule") {
            Toggle("All-day", isOn: $allDay)
                .onChange(of: allDay) { _, isAllDay in
                    if isAllDay {
                        task.startAt = nil
                        task.endAt = nil
                    } else {
                        let anchor = task.dueAt ?? Date.now
                        task.dueAt = anchor
                        task.startAt = anchor
                        task.endAt = nil
                    }
                    save()
                }

            dateRow("Due") {
                NexusDateField(
                    date: dueAtBinding,
                    components: allDay ? [.date] : [.date, .hourAndMinute],
                    accessibilityLabel: "Due date"
                )
            }

            if allDay {
                Text("Timed schedule disabled in all-day mode")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                dateRow("Start") {
                    NexusDateField(
                        date: startAtBinding,
                        components: [.date, .hourAndMinute],
                        accessibilityLabel: "Start time"
                    )
                }

                dateRow("End") {
                    NexusDateField(
                        date: endAtBinding,
                        components: [.date, .hourAndMinute],
                        minDate: task.startAt.map { minimumEndDate(after: $0) },
                        isEnabled: task.startAt != nil,
                        accessibilityLabel: "End time"
                    )
                }

                if let durationLabel {
                    Text("Duration: \(durationLabel)")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
        }
    }

    /// A labelled field row: caption on the left, control on the right.
    @ViewBuilder
    func dateRow<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
            Spacer(minLength: 8)
            field()
        }
    }

    var recurrenceCard: some View {
        inspectorCard("Recurrence") {
            Picker("Repeat", selection: $recurrenceChoice) {
                ForEach(RecurrenceChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .onChange(of: recurrenceChoice) { _, choice in
                if let rule = choice.rrule {
                    task.recurrenceRule = rule
                } else if choice == .custom {
                    customRRule = task.recurrenceRule ?? ""
                } else {
                    task.recurrenceRule = nil
                }
                save()
            }
            if recurrenceChoice == .custom {
                TextField("RRULE", text: $customRRule)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .onSubmit {
                        task.recurrenceRule = customRRule.isEmpty ? nil : customRRule
                        save()
                    }
            }
        }
    }

    var notesCard: some View {
        inspectorCard("Notes") {
            TextEditor(text: $notesDraft)
                .font(NexusType.body)
                .foregroundStyle(NexusColor.Text.primary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 120)
                .background(
                    NexusColor.Background.control,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(NexusColor.Line.hairline, lineWidth: 1)
                }
                .onChange(of: notesDraft) { _, _ in saveNotesDebounced() }
        }
    }

    func inspectorCard<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NexusCard(.elev2, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title.uppercased())
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var priorityStatusChip: some View {
        // Lime economy: priority is metadata → neutral; High keeps its glyph.
        NexusChip(
            priorityLabel(for: task.priority),
            systemImage: task.priority == .high ? "exclamationmark" : nil,
            tone: .neutral
        )
    }

    @ViewBuilder
    private var lifecycleChip: some View {
        if !incomingBlockerTasks.isEmpty {
            NexusChip("Blocked", systemImage: "lock.fill", tone: .rose)
        } else {
            switch task.status {
            case .open:
                NexusChip("Open")
            case .done:
                // Lime economy: done-state is metadata → neutral; glyph reads "done".
                NexusChip("Done", systemImage: "checkmark.circle.fill", tone: .neutral)
            case .snoozed:
                NexusChip("Snoozed", systemImage: "clock")
            }
        }
    }

    private var dueChipLabel: String? {
        guard let dueAt = task.dueAt else { return nil }
        if isOverdue { return "Overdue" }
        return dueAt.formatted(date: .abbreviated, time: allDay ? .omitted : .shortened)
    }

    private var isOverdue: Bool {
        guard let dueAt = task.dueAt, task.status != .done else { return false }
        return dueAt < Date.now
    }

    private func priorityLabel(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "P1"
        case .medium: return "P2"
        case .low: return "P3"
        case .none: return "No priority"
        }
    }

    private var dueAtBinding: Binding<Date> {
        Binding(
            get: { task.dueAt ?? .now },
            set: {
                let previousStart = task.startAt
                let previousEnd = task.endAt
                task.dueAt = $0
                if !allDay {
                    moveStart(to: $0, previousStart: previousStart, previousEnd: previousEnd)
                }
                save()  // persist on edit (was the removed DatePicker's onChange)
            }
        )
    }

    private var startAtBinding: Binding<Date> {
        Binding(
            get: { task.startAt ?? task.dueAt ?? .now },
            set: {
                moveStart(to: $0, previousStart: task.startAt, previousEnd: task.endAt)
                save()
            }
        )
    }

    private var endAtBinding: Binding<Date> {
        Binding(
            get: {
                guard let startAt = task.startAt else {
                    return (task.dueAt ?? .now).addingTimeInterval(3_600)
                }
                let minimumEndAt = minimumEndDate(after: startAt)
                guard let endAt = task.endAt, endAt >= minimumEndAt else {
                    return startAt.addingTimeInterval(3_600)
                }
                return endAt
            },
            set: {
                guard let startAt = task.startAt, $0 >= minimumEndDate(after: startAt) else {
                    return
                }
                task.endAt = $0
                save()
            }
        )
    }

    private var durationLabel: String? {
        guard let startAt = task.startAt, let endAt = task.endAt, endAt > startAt else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: endAt.timeIntervalSince(startAt))
    }

    private var priorityBinding: Binding<TaskPriority> {
        Binding(
            get: { task.priority },
            set: { task.priorityRaw = $0.rawValue }
        )
    }

    private func minimumEndDate(after startAt: Date) -> Date {
        startAt.addingTimeInterval(60)
    }

    @MainActor
    private func moveStart(to newStart: Date, previousStart: Date?, previousEnd: Date?) {
        task.startAt = newStart
        guard let previousStart, let previousEnd, previousEnd > previousStart else {
            task.endAt = nil
            return
        }
        task.endAt = newStart.addingTimeInterval(previousEnd.timeIntervalSince(previousStart))
    }

    @MainActor
    private func save() {
        guard let repository else { return }
        try? repository.update(task) { _ in }
    }

    @MainActor
    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = _Concurrency.Task { @MainActor [weak repository] in
            try? await _Concurrency.Task.sleep(for: .seconds(1))
            if _Concurrency.Task.isCancelled { return }
            guard let repository else { return }
            try? repository.update(task) { _ in }
        }
    }

    @MainActor
    private func loadNotesDraft() {
        notesSaveTask?.cancel()
        notesDraft = (try? TaskNoteContent.markdown(for: task, in: modelContext)) ?? task.body
    }

    @MainActor
    private func saveNotesDebounced() {
        notesSaveTask?.cancel()
        notesSaveTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(1))
            if _Concurrency.Task.isCancelled { return }
            saveNotes()
        }
    }

    @MainActor
    private func saveNotes() {
        let noteRepository = NoteRepository(context: modelContext, tasks: repository, now: Date.init)

        do {
            try TaskNoteContent.replaceMarkdown(notesDraft, for: task, in: modelContext, repository: noteRepository)
            try repository?.update(task) { _ in }
        } catch {
            // Keep the editor responsive; the next explicit save/reload will retry through the same path.
        }
    }
}

enum TaskDetailRecurrenceChoice: String, Identifiable, CaseIterable {
    case none, daily, weekly, monthly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom RRULE"
        }
    }
    var rrule: String? {
        switch self {
        case .none: return nil
        case .daily: return "FREQ=DAILY"
        case .weekly: return "FREQ=WEEKLY"
        case .monthly: return "FREQ=MONTHLY"
        case .custom: return nil
        }
    }
    static func from(rrule: String?) -> Self {
        guard let rrule else { return .none }
        switch rrule {
        case "FREQ=DAILY": return .daily
        case "FREQ=WEEKLY": return .weekly
        case "FREQ=MONTHLY": return .monthly
        default: return .custom
        }
    }
}

extension TaskDetailInspector {
    /// Eyebrow over a full-width segmented control: a leading picker label
    /// hyphenated "Priority" → "Priori-ty" in the ~360 panel.
    fileprivate var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRIORITY")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            Picker("Priority", selection: priorityBinding) {
                Text("None").tag(TaskPriority.none)
                Text("Low").tag(TaskPriority.low)
                Text("Medium").tag(TaskPriority.medium)
                Text("High").tag(TaskPriority.high)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: task.priorityRaw) { _, _ in save() }
        }
    }

    var deadlineCard: some View {
        inspectorCard("Deadline") {
            Toggle("Deadline", isOn: deadlineEnabledBinding)

            if task.deadlineAt != nil {
                dateRow("Date") {
                    NexusDateField(
                        date: deadlineAtBinding,
                        components: [.date],
                        accessibilityLabel: "Deadline date"
                    )
                }

                Button("Clear deadline", role: .destructive) {
                    task.deadlineAt = nil
                    saveDeadlineChange()
                }
                .buttonStyle(.plain)
                // MP-2 burned: destructive action text renders via primary ink
                .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }

    fileprivate var deadlineEnabledBinding: Binding<Bool> {
        Binding(
            get: { task.deadlineAt != nil },
            set: { isEnabled in
                if isEnabled, task.deadlineAt == nil {
                    task.deadlineAt = task.dueAt ?? Date.now
                    saveDeadlineChange()
                } else if !isEnabled, task.deadlineAt != nil {
                    task.deadlineAt = nil
                    saveDeadlineChange()
                }
            }
        )
    }

    fileprivate var deadlineAtBinding: Binding<Date> {
        Binding(
            get: { task.deadlineAt ?? task.dueAt ?? .now },
            set: {
                task.deadlineAt = $0
                saveDeadlineChange()
            }
        )
    }

    @MainActor
    func saveDeadlineChange() {
        if let repository {
            try? repository.update(task) { _ in }
        } else {
            task.updatedAt = Date.now
            try? modelContext.save()
        }
    }
}

@MainActor
struct TaskDetailInspectorBlocksActions {
    let task: TaskItem
    let linkRepository: LinkRepository

    func addBlock(target: TaskItem) throws {
        _ = try linkRepository.findOrCreate(
            from: (.task, task.id),
            to: (.task, target.id),
            linkKind: .blocks
        )
    }

    func removeBlock(targetID: UUID) throws {
        let outgoing = try linkRepository.outgoingBlocks(from: (.task, task.id))
        guard let link = outgoing.first(where: { $0.toKind == .task && $0.toID == targetID })
        else { return }
        try linkRepository.delete(link)
    }

    func removeBlock(linkID: UUID) throws {
        let outgoing = try linkRepository.outgoingBlocks(from: (.task, task.id))
        guard let link = outgoing.first(where: { $0.id == linkID }) else { return }
        try linkRepository.delete(link)
    }
}
