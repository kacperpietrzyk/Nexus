import NexusCore
import NexusUI
import SwiftUI

/// Add a manual scheduled block (spec §7): pick an open task, set a time range, and
/// create an `accepted` / `manual` block (materialized as a mirror event when a
/// writer is available). Distinct from the scheduler's `proposed` blocks.
struct ManualBlockView: View {
    let tasks: [(id: UUID, title: String)]
    let anchor: Date
    let onAdd: (UUID, String, Date, Date) -> Void
    let onCancel: () -> Void

    @State private var selectedTaskID: UUID?
    @State private var start: Date
    @State private var end: Date

    init(
        tasks: [(id: UUID, title: String)],
        anchor: Date,
        onAdd: @escaping (UUID, String, Date, Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.tasks = tasks
        self.anchor = anchor
        self.onAdd = onAdd
        self.onCancel = onCancel
        let calendar = Calendar.current
        let base =
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: anchor)
            ?? anchor
        _start = State(initialValue: base)
        _end = State(initialValue: base.addingTimeInterval(3600))
        _selectedTaskID = State(initialValue: tasks.first?.id)
    }

    var body: some View {
        Form {
            Section("Task") {
                if tasks.isEmpty {
                    Text("No open tasks to schedule.")
                        .font(NexusType.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                } else {
                    NexusSelect(
                        selection: $selectedTaskID,
                        options: tasks.map { Optional($0.id) },
                        label: { id in tasks.first { $0.id == id }?.title ?? "" },
                        accessibilityLabel: "Task"
                    )
                }
            }

            Section("Time") {
                NexusDateField(date: $start, components: [.date, .hourAndMinute], accessibilityLabel: "Starts")
                NexusDateField(date: $end, components: [.date, .hourAndMinute], accessibilityLabel: "Ends")
            }

            Section {
                Button("Add block", action: add)
                    .disabled(selectedTaskID == nil || end <= start)
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        guard let taskID = selectedTaskID else { return }
        let title = tasks.first { $0.id == taskID }?.title ?? ""
        onAdd(taskID, title, start, max(end, start.addingTimeInterval(900)))
    }
}
