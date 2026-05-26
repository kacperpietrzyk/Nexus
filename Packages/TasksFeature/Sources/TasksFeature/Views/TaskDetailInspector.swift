import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Card-based editor for a single task. Auto-saves on field commit via
/// `TaskItemRepository.update`. Recurrence picker emits curated RRULE
/// strings; "Custom" path leaves the existing rule untouched and surfaces
/// a text field for direct editing.
public struct TaskDetailInspector: View {

    @Environment(\.modelContext) var modelContext
    @Environment(\.taskRepository) var repository

    @Bindable public var task: TaskItem
    public let onClose: (() -> Void)?

    @State private var allDay: Bool
    @State private var recurrenceChoice: RecurrenceChoice
    @State private var customRRule: String
    @State private var saveTask: _Concurrency.Task<Void, Never>?
    @State var outgoingBlockedTasks: [TaskItem] = []
    @State var incomingBlockerTasks: [TaskItem] = []
    @State var blockSearchText: String = ""
    @State var blockSearchCandidates: [TaskItem] = []
    @State var parentTaskPicker = TaskParentPickerState()
    @State var subtaskActionError: String?

    public init(task: TaskItem, onClose: (() -> Void)? = nil) {
        self._task = Bindable(task)
        self.onClose = onClose
        self._allDay = State(initialValue: task.startAt == nil)
        self._recurrenceChoice = State(
            initialValue: RecurrenceChoice.from(rrule: task.recurrenceRule)
        )
        self._customRRule = State(initialValue: task.recurrenceRule ?? "")
    }

    public var body: some View {
        ZStack {
            NexusWallpaper()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    headerCard
                    aiAssistCard
                    scheduleCard
                    deadlineCard
                    recurrenceCard
                    linksCard
                    notesCard
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
        .background(NexusColor.Background.base)
        .navigationTitle(task.title.isEmpty ? "Task" : task.title)
        .task { loadLinkState() }
        .onChange(of: task.id) { _, _ in loadLinkState() }
        .onKeyPress(.escape) {
            onClose?()
            return onClose == nil ? .ignored : .handled
        }
    }

    private var headerCard: some View {
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
                    NexusChip(
                        dueChipLabel,
                        systemImage: isOverdue ? "exclamationmark.triangle.fill" : "calendar",
                        tone: isOverdue ? .rose : .accent
                    )
                }
                Spacer(minLength: 0)
            }

            Picker("Priority", selection: priorityBinding) {
                Text("None").tag(TaskPriority.none)
                Text("Low").tag(TaskPriority.low)
                Text("Medium").tag(TaskPriority.medium)
                Text("High").tag(TaskPriority.high)
            }
            .pickerStyle(.segmented)
            .onChange(of: task.priorityRaw) { _, _ in save() }

            Toggle("Pin as focus", isOn: $task.pinnedAsFocus)
                .onChange(of: task.pinnedAsFocus) { _, _ in save() }

            TagsEditor(tags: $task.tags) { save() }
        }
    }

    private var aiAssistCard: some View {
        inspectorCard("AI Assist") {
            TaskAssistButtonGroup(task: task)
        }
    }

    private var scheduleCard: some View {
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

            DatePicker(
                "Due",
                selection: dueAtBinding,
                displayedComponents: allDay ? .date : [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .onChange(of: task.dueAt) { _, _ in save() }

            if allDay {
                Text("Timed schedule disabled in all-day mode")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                DatePicker(
                    "Start",
                    selection: startAtBinding,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)

                if let startAt = task.startAt {
                    DatePicker(
                        "End",
                        selection: endAtBinding,
                        in: minimumEndDate(after: startAt)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                } else {
                    DatePicker(
                        "End",
                        selection: endAtBinding,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .disabled(true)
                }

                if let durationLabel {
                    Text("Duration: \(durationLabel)")
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
        }
    }

    private var recurrenceCard: some View {
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

    private var notesCard: some View {
        inspectorCard("Notes") {
            TextEditor(text: $task.body)
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
                .onChange(of: task.body) { _, _ in saveDebounced() }
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
        NexusChip(
            priorityLabel(for: task.priority),
            systemImage: task.priority == .high ? "exclamationmark" : nil,
            tone: task.priority == .high ? .accent : .neutral
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
                NexusChip("Done", systemImage: "checkmark.circle.fill", tone: .accent)
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

    enum RecurrenceChoice: String, Identifiable, CaseIterable {
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
        static func from(rrule: String?) -> RecurrenceChoice {
            guard let rrule else { return .none }
            switch rrule {
            case "FREQ=DAILY": return .daily
            case "FREQ=WEEKLY": return .weekly
            case "FREQ=MONTHLY": return .monthly
            default: return .custom
            }
        }
    }
}

extension TaskDetailInspector {
    fileprivate var deadlineCard: some View {
        inspectorCard("Deadline") {
            Toggle("Deadline", isOn: deadlineEnabledBinding)

            if task.deadlineAt != nil {
                DatePicker(
                    "Date",
                    selection: deadlineAtBinding,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)

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
    fileprivate func saveDeadlineChange() {
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

private struct TagsEditor: View {
    @Binding var tags: [String]
    let onChange: () -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    NexusChip("#\(tag)", systemImage: "xmark.circle.fill")
                        .onTapGesture {
                            tags.removeAll { $0 == tag }
                            onChange()
                        }
                }
            }
            HStack {
                tagDraftField
                Button("Add") {
                    let cleaned = draft.trimmingCharacters(in: .whitespaces).lowercased()
                    guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
                    tags.append(cleaned)
                    draft = ""
                    onChange()
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var tagDraftField: some View {
        #if os(iOS)
        TextField("New tag", text: $draft)
            .textInputAutocapitalization(.never)
        #else
        TextField("New tag", text: $draft)
        #endif
    }
}
