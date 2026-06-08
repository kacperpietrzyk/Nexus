import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// In-list refinement of the resolved task list by a structural label (any
/// group — gate/domain/free) and/or an assigned agent (Projects tier, spec §7 /
/// §8). This is a *refinement within a list*, NOT a new navigation destination,
/// so it never touches the `TaskFilter` enum: it post-filters the arrays
/// `TaskListView.reload()` already resolved. Both selections are AND-combined;
/// `nil` on either side means "don't constrain on that axis".
struct TaskListRefinement: Equatable {
    var labelID: UUID?
    var agent: AgentAssignee?

    var isActive: Bool { labelID != nil || agent != nil }

    /// The set of task ids carrying `labelID`, via the `.labeled` backlinks (one
    /// query, not N per-task resolutions). `nil` when no label is selected.
    @MainActor
    func labeledTaskIDs(in context: ModelContext) -> Set<UUID>? {
        guard let labelID else { return nil }
        let links = LinkRepository(context: context)
        let edges = (try? links.backlinks(to: (.label, labelID))) ?? []
        return Set(edges.filter { $0.fromKind == .task }.map(\.fromID))
    }

    /// Whether a task survives this refinement (AND across both axes). The label
    /// id-set is precomputed by the caller; the agent axis is a direct field
    /// compare (`assignedAgent`, invariant I8 metadata).
    func keeps(_ task: TaskItem, labeledTaskIDs: Set<UUID>?) -> Bool {
        if let labeledTaskIDs, !labeledTaskIDs.contains(task.id) { return false }
        if let agentRaw = agent?.rawValue, task.assignedAgent != agentRaw { return false }
        return true
    }
}

extension TaskListView {

    /// Loads the label set offered by the filter bar (all active labels). Cheap;
    /// runs once on appear. Lives here (not in TaskListView.swift) to keep that
    /// file's type body under the lint budget.
    @MainActor
    func loadRefinementLabels() {
        let repository = LabelRepository(context: modelContext)
        refinementLabels = (try? repository.allActive()) ?? []
    }

    /// Final post-resolution pass (spec §7 / §8): intersects the resolved arrays
    /// with the active refinement. Runs once at the end of `reload()`, so it
    /// composes uniformly with every `TaskFilter` case — no `TaskFilter` cases
    /// added (advisor note: refinement-within-a-list, not a new destination).
    @MainActor
    func applyRefinement() {
        guard refinement.isActive else { return }
        let labeledIDs = refinement.labeledTaskIDs(in: modelContext)
        func keep(_ task: TaskItem) -> Bool {
            refinement.keeps(task, labeledTaskIDs: labeledIDs)
        }
        overdue = overdue.filter(keep)
        today = today.filter(keep)
        noDate = noDate.filter(keep)
        flatList = flatList.filter(keep)
    }
}

/// Compact filter bar above the task list: a label menu (grouped) and an agent
/// menu. Achromatic chrome; a single "Clear" affordance when active.
struct TaskListFilterBar: View {
    @Binding var refinement: TaskListRefinement
    let availableLabels: [TaskLabel]

    var body: some View {
        if !availableLabels.isEmpty {
            HStack(spacing: 8) {
                labelMenu
                agentMenu
                if refinement.isActive {
                    Button("Clear") { refinement = TaskListRefinement() }
                        .buttonStyle(.plain)
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .accessibilityLabel("Clear filters")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(NexusColor.Background.base)
            .tint(NexusColor.Text.primary)
        }
    }

    private var labelMenu: some View {
        Menu {
            Button("All labels") { refinement.labelID = nil }
            ForEach(LabelGroup.allCases, id: \.self) { group in
                let options = availableLabels.filter { $0.group == group }
                if !options.isEmpty {
                    Section(groupTitle(group)) {
                        ForEach(options, id: \.id) { label in
                            Button(label.name) { refinement.labelID = label.id }
                        }
                    }
                }
            }
        } label: {
            filterChip(systemImage: "tag", text: selectedLabelName ?? "Label")
        }
    }

    private var agentMenu: some View {
        Menu {
            Button("Any agent") { refinement.agent = nil }
            ForEach(AgentAssignee.allCases, id: \.self) { agent in
                Button(agentName(agent)) { refinement.agent = agent }
            }
        } label: {
            filterChip(systemImage: "person", text: refinement.agent.map(agentName) ?? "Agent")
        }
    }

    private func filterChip(systemImage: String, text: String) -> some View {
        NexusChip(text, systemImage: systemImage, tone: .neutral)
    }

    private var selectedLabelName: String? {
        guard let id = refinement.labelID else { return nil }
        return availableLabels.first { $0.id == id }?.name
    }

    private func groupTitle(_ group: LabelGroup) -> String {
        switch group {
        case .domain: return "Domain"
        case .gate: return "Gate"
        case .free: return "Labels"
        }
    }

    private func agentName(_ agent: AgentAssignee) -> String {
        switch agent {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
}
