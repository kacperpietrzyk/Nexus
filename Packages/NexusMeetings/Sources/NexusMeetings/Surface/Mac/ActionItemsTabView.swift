import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI
import TasksFeature

public struct ActionItemsTabView: View {
    private let meetingID: UUID
    private let composition: MeetingsComposition
    /// Called when the user requests opening a task in the app's task detail.
    /// Supplied by the host; `nil` hides the "Open Task" menu item.
    private let openTask: ((TaskItem) -> Void)?

    @State private var actionItems: [TaskItem] = []

    public init(
        meetingID: UUID,
        composition: MeetingsComposition,
        openTask: ((TaskItem) -> Void)? = nil
    ) {
        self.meetingID = meetingID
        self.composition = composition
        self.openTask = openTask
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text("ACTION ITEMS")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                if !actionItems.isEmpty {
                    NexusCount(
                        value: actionItems.count,
                        font: NexusType.mono,
                        color: NexusColor.Text.disabled)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if actionItems.isEmpty {
                ActionItemsEmptyState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(actionItems, id: \.id) { task in
                            ActionItemRow(
                                task: task,
                                onToggle: { toggleDone(task) },
                                onCopy: { copyAsMarkdown(task) },
                                onOpen: openTask.map { callback in { callback(task) } }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            reload()
        }
        // Also refresh on remote/cross-process store changes (CloudKit imports and
        // helper-process writes post .NSPersistentStoreRemoteChange, not didSave).
        .reloadOnStoreChange { reload() }
    }

    // MARK: - Actions

    private func toggleDone(_ task: TaskItem) {
        do {
            if task.status == .done {
                try composition.taskItemRepository.reopen(task)
            } else {
                try TaskCompletionAction.completeOrCascade(
                    task, repository: composition.taskItemRepository)
            }
        } catch {
            // Best-effort: a failed toggle leaves the row unchanged; the
            // store-change observer will reload to reflect real state.
        }
    }

    private func copyAsMarkdown(_ task: TaskItem) {
        let markdown = MarkdownExport.checklistItem(task.title, done: task.status == .done)
        PasteboardCopy.string(markdown)
    }

    private func reload() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID) else {
            actionItems = []
            return
        }

        let ids = meeting.actionItemIDs
        guard !ids.isEmpty else {
            actionItems = []
            return
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                ids.contains(task.id) && task.deletedAt == nil
            }
        )

        guard let fetched = try? composition.meetingRepository.context.fetch(descriptor) else {
            actionItems = []
            return
        }

        // Synced TaskItem ids are not unique (CloudKit forbids @Attribute(.unique)); a sync
        // conflict can yield duplicate ids. Dedup keep-first instead of trapping on the dup.
        let tasksByID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        actionItems = ids.compactMap { tasksByID[$0] }
    }
}

// MARK: - Row

private struct ActionItemRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onOpen: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Tappable status glyph — toggles done state.
            Button(action: onToggle) {
                NexusStatusGlyph(nexusStatus)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(task.status == .done ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(NexusType.body)
                    .foregroundStyle(
                        task.status == .done ? NexusColor.Text.tertiary : NexusColor.Text.primary
                    )
                    .strikethrough(task.status == .done, color: NexusColor.Text.disabled)

                let taskBody = ((try? TaskNoteContent.plainText(for: task, in: modelContext)) ?? task.body)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !taskBody.isEmpty {
                    Text(taskBody)
                        .font(NexusType.bodySmall)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(2)
                }

                if let dueAt = task.dueAt {
                    NexusChip(dueAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NexusColor.Line.hairline).frame(height: 1)
        }
        .contextMenu {
            Button {
                onToggle()
            } label: {
                Label(
                    task.status == .done ? "Mark Incomplete" : "Mark Complete",
                    systemImage: task.status == .done ? "circle" : "checkmark.circle"
                )
            }

            if let onOpen {
                Button {
                    onOpen()
                } label: {
                    Label("Open Task", systemImage: "arrow.up.right.square")
                }
            }

            Divider()

            Button {
                onCopy()
            } label: {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }
        }
    }

    private var nexusStatus: NexusStatus {
        switch task.status {
        case .open: return .todo
        case .done: return .done
        case .snoozed: return .inReview
        }
    }
}

private struct ActionItemsEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NexusColor.Text.muted)
            Text("No action items")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.secondary)
            Text("Nothing was extracted from this meeting.")
                .font(NexusType.meta)
                .foregroundStyle(NexusColor.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 120)
    }
}
