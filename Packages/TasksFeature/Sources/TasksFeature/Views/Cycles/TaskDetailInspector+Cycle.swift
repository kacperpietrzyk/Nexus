import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Cycle assignment card (Tranche 2 Plan C), split out per the Comments/
/// Reminders extension pattern. Every write routes through
/// `TaskItemRepository.assignCycle` — the single path that validates the
/// target, bumps `updatedAt`, and records the `cycleChanged` activity event.
extension TaskDetailInspector {
    var cycleCard: some View {
        inspectorCard("Cycle") {
            CycleAssignmentPicker(task: task)
        }
    }
}

/// Tagged selection so the picker can represent "no cycle" (nil) alongside a
/// concrete cycle id — the `WorkflowStateSelection`/`AgentSelection` idiom.
enum CycleAssignmentSelection: Hashable {
    case none
    case assigned(UUID)

    static func from(cycleID: UUID?) -> CycleAssignmentSelection {
        cycleID.map(CycleAssignmentSelection.assigned) ?? .none
    }

    var cycleID: UUID? {
        if case .assigned(let id) = self { return id }
        return nil
    }
}

struct CycleAssignmentPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.taskRepository) private var repository

    @Bindable var task: TaskItem

    @State private var cycles: [Cycle] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Cycle", selection: selectionBinding) {
                Text("No cycle").tag(CycleAssignmentSelection.none)
                ForEach(cycles, id: \.id) { cycle in
                    Text(cycle.name).tag(CycleAssignmentSelection.assigned(cycle.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if let error {
                Text(error)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)
            }
        }
        .task { loadCycles() }
        .onChange(of: task.id) { _, _ in loadCycles() }
    }

    private var selectionBinding: Binding<CycleAssignmentSelection> {
        Binding(
            get: { CycleAssignmentSelection.from(cycleID: task.cycleID) },
            set: { selection in assign(selection.cycleID) }
        )
    }

    /// Pickable cycles: live and not completed; PLUS the task's currently
    /// assigned cycle even if completed, so the menu can render the current
    /// value instead of falling back to "No cycle".
    @MainActor
    private func loadCycles() {
        let repository = CycleRepository(context: modelContext)
        var loaded = (try? repository.allActive())?.filter { $0.status != .completed } ?? []
        if let assignedID = task.cycleID, !loaded.contains(where: { $0.id == assignedID }) {
            if let assigned = try? repository.find(id: assignedID), assigned.deletedAt == nil {
                loaded.append(assigned)
            }
        }
        cycles = loaded
    }

    @MainActor
    private func assign(_ cycleID: UUID?) {
        guard let repository else { return }
        guard task.cycleID != cycleID else { return }
        do {
            try repository.assignCycle(task, to: cycleID)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}
