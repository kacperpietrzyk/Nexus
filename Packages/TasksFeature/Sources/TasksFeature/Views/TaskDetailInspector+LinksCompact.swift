import NexusCore
import NexusUI
import SwiftUI

// Compact "Links" card for the Mac centered modal (`.wide` layout). The full
// inline `linksCard` (see +Links.swift) eagerly lists up to 8 parent/block
// candidates inline, which made the dialog tall — that one stays on the iOS
// `.column` layout. Here the card shows only the CURRENT relationships
// (chips/labels) and moves the add-pickers into popovers, so it stays short and
// never grows the modal. All state + actions are reused from +Links.swift.
extension TaskDetailInspector {

    var linksCompactCard: some View {
        inspectorCard("Links") {
            // Parent: current parent chip (removable) or a "Set parent" popover.
            HStack(spacing: 8) {
                Text("Parent")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                Spacer(minLength: 8)
                if let parent = parentTaskPicker.parent {
                    NexusChip(
                        parent.title,
                        systemImage: "arrow.turn.down.right",
                        tone: .neutral,
                        onRemove: clearParentTask
                    )
                } else {
                    Button {
                        parentPickerPresented = true
                    } label: {
                        Label("Set parent", systemImage: "arrow.turn.down.right")
                            .font(NexusType.bodySmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .popover(isPresented: $parentPickerPresented, arrowEdge: .bottom) {
                        parentPickerPopover
                    }
                }
            }

            // Subtasks: a single compact "New subtask" action.
            HStack(spacing: 8) {
                Text("Subtasks")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                Spacer(minLength: 8)
                Button {
                    createNewSubtask()
                } label: {
                    Label("New subtask", systemImage: "plus")
                        .font(NexusType.bodySmall)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NexusColor.Text.secondary)
            }
            if let subtaskActionError {
                Text(subtaskActionError)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
            }

            // Blocks: current outgoing chips + an "Add" popover.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Blocks")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.muted)
                    if !outgoingBlockedTasks.isEmpty {
                        // Blocked count (spec §9): how many tasks this one blocks.
                        Text("\(outgoingBlockedTasks.count)")
                            .nexusType(.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .accessibilityLabel("Blocks \(outgoingBlockedTasks.count) tasks")
                    }
                    Spacer()
                    Button {
                        blockPickerPresented = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(NexusType.bodySmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .popover(isPresented: $blockPickerPresented, arrowEdge: .bottom) {
                        blockPickerPopover
                    }
                }
                outgoingBlocksList
            }

            // Blocked by: read-only chips (only when something blocks this task).
            if !incomingBlockerTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blocked by")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.primary)
                    blockedByList
                }
            }
        }
    }

    private var parentPickerPopover: some View {
        pickerPopover(
            LinkPicker(
                title: "Make subtask of…",
                placeholder: "Find parent task",
                text: $parentTaskPicker.searchText,
                onSearch: refreshParentCandidates,
                candidates: parentTaskPicker.candidates,
                emptyLabel: "No eligible tasks",
                onPick: { candidate in
                    assignParentTask(candidate)
                    parentPickerPresented = false
                }
            )
        )
    }

    private var blockPickerPopover: some View {
        pickerPopover(
            LinkPicker(
                title: "Block a task",
                placeholder: "Block another task…",
                text: $blockSearchText,
                onSearch: refreshBlockCandidates,
                candidates: blockSearchCandidates,
                emptyLabel: "No open tasks to block",
                onPick: { candidate in
                    addBlock(target: candidate)
                    blockPickerPresented = false
                }
            )
        )
    }

    /// Config for a link-picker popover (search field + candidate list).
    struct LinkPicker {
        let title: String
        let placeholder: String
        let text: Binding<String>
        let onSearch: () -> Void
        let candidates: [TaskItem]
        let emptyLabel: String
        let onPick: (TaskItem) -> Void
    }

    @ViewBuilder
    private func pickerPopover(_ picker: LinkPicker) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(picker.title)
                .nexusType(.caption)
                .foregroundStyle(NexusColor.Text.muted)
            TextField(picker.placeholder, text: picker.text)
                .onChange(of: picker.text.wrappedValue) { _, _ in picker.onSearch() }
            if picker.candidates.isEmpty {
                Text(picker.emptyLabel)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                ForEach(picker.candidates, id: \.id) { candidate in
                    Button {
                        picker.onPick(candidate)
                    } label: {
                        HStack {
                            Text(candidate.title)
                                .foregroundStyle(NexusColor.Text.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(NexusColor.Text.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pick \(candidate.title)")
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
