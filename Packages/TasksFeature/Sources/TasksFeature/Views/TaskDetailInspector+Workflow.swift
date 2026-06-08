import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Tracker controls for a task that belongs to a project (Projects tier, spec
/// §5 / §8): the optional `WorkflowState` machine and the `AgentAssignee`
/// picker. Both are gated on `task.projectID != nil` — a plain GTD task (Inbox /
/// personal) never shows the machine and keeps the today's open/done UI
/// (invariant I7).
///
/// Every workflow mutation routes through `TaskItemRepository.setWorkflowState`,
/// the single reconciliation write path (spec §5.3) — the UI never sets a raw
/// `status`. Agent assignment is pure metadata (invariant I8), so it goes through
/// the plain `update` hook.
extension TaskDetailInspector {

    /// Visible only for project tasks (spec §5: the machine is opt-in per task).
    var showsWorkflowCard: Bool { task.projectID != nil }

    @ViewBuilder
    var workflowCard: some View {
        if showsWorkflowCard {
            inspectorCard("Workflow") {
                workflowStatePicker
                agentPicker
            }
        }
    }

    // MARK: - WorkflowState (spec §5)

    /// State picker for a project task. `nil` (GTD) maps to a "Not started"
    /// sentinel so the user can opt the task into the machine; any concrete pick
    /// drives `status` deterministically via `setWorkflowState` (reconciliation).
    private var workflowStatePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATE")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            Picker("State", selection: workflowSelectionBinding) {
                Text("Not started").tag(WorkflowStateSelection.unset)
                ForEach(WorkflowState.allCases, id: \.self) { state in
                    Text(workflowLabel(state)).tag(WorkflowStateSelection.set(state))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// Drives the picker. `get` reflects the current `workflowState` (nil → unset).
    /// `set` routes a concrete pick through `setWorkflowState` (spec §5.3 — the
    /// sole reconciliation path); `unset` is inert (no demote-to-GTD in scope).
    private var workflowSelectionBinding: Binding<WorkflowStateSelection> {
        Binding(
            get: { task.workflowState.map(WorkflowStateSelection.set) ?? .unset },
            set: { selection in
                guard case .set(let state) = selection else { return }
                applyWorkflowState(state)
            }
        )
    }

    @MainActor
    private func applyWorkflowState(_ state: WorkflowState) {
        guard let repository, task.workflowState != state else { return }
        try? repository.setWorkflowState(state, on: task)
    }

    private func workflowLabel(_ state: WorkflowState) -> String {
        switch state {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        case .canceled: return "Canceled"
        case .duplicate: return "Duplicate"
        }
    }

    // MARK: - Agent assignment (spec §8)

    /// Agent picker. `nil` = self (the user). Pure metadata — assignment never
    /// affects scheduling/visibility (invariant I8), so it writes via the plain
    /// `update` hook. The auto-derive suggestion (`suggestedAgent(forLabels:)`)
    /// surfaces below as an editable hint, never an override.
    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AGENT")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            Picker("Agent", selection: agentSelectionBinding) {
                Text("Me").tag(AgentSelection.none)
                ForEach(AgentAssignee.allCases, id: \.self) { agent in
                    Text(agentLabel(agent)).tag(AgentSelection.assigned(agent))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            agentSuggestionHint
        }
    }

    /// Surfaces the label-derived agent suggestion when it differs from the
    /// current assignment — a one-tap hint, never an automatic override (spec §8).
    @ViewBuilder
    private var agentSuggestionHint: some View {
        if let suggestion = suggestedAgent(forLabels: assignedLabels), suggestion != task.agent {
            Button {
                assignAgent(suggestion)
            } label: {
                Label("Suggested: \(agentLabel(suggestion))", systemImage: "wand.and.stars")
                    .font(NexusType.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NexusColor.Text.tertiary)
            .accessibilityLabel("Assign suggested agent \(agentLabel(suggestion))")
        }
    }

    private var agentSelectionBinding: Binding<AgentSelection> {
        Binding(
            get: { task.agent.map(AgentSelection.assigned) ?? .none },
            set: { selection in
                switch selection {
                case .none: assignAgent(nil)
                case .assigned(let agent): assignAgent(agent)
                }
            }
        )
    }

    @MainActor
    private func assignAgent(_ agent: AgentAssignee?) {
        guard let repository else { return }
        try? repository.update(task) { item in
            item.assignedAgent = agent?.rawValue
        }
    }

    private func agentLabel(_ agent: AgentAssignee) -> String {
        switch agent {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
}

/// Tagged selection so the workflow picker can represent the nil (GTD) state
/// alongside the seven concrete `WorkflowState` cases without an optional tag.
enum WorkflowStateSelection: Hashable {
    case unset
    case set(WorkflowState)
}

/// Tagged selection so the agent picker can represent "self" (nil) alongside the
/// concrete `AgentAssignee` cases.
enum AgentSelection: Hashable {
    case none
    case assigned(AgentAssignee)
}
