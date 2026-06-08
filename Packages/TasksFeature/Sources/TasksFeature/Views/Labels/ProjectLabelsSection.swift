import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Labels section for a project (Projects tier, spec §7 — labels hang off both
/// task and project endpoints via `LinkKind.labeled`). Mirrors the task inspector's
/// label affordances: single-select `domain`/`gate` group pickers (the repo
/// enforces I5) plus additive `free` labels, achromatic glyphs (`LabelChipRow`),
/// system labels non-deletable. Built ad-hoc from `modelContext` (the established
/// repo-in-view convention).
struct ProjectLabelsSection: View {
    @Environment(\.modelContext) private var modelContext

    let projectID: UUID

    @State private var assigned: [TaskLabel] = []
    @State private var available: [TaskLabel] = []
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Labels")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            if assigned.isEmpty {
                Text("No labels")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            } else {
                FlowLabels.removable(labels: assigned) { label in remove(label) }
            }

            groupPickers
            freeCreator
        }
        .task(id: projectID) { load() }
    }

    private var endpoint: (LabelEndpointKind, UUID) { (.project, projectID) }

    @ViewBuilder
    private var groupPickers: some View {
        ForEach([LabelGroup.domain, LabelGroup.gate], id: \.self) { group in
            let options = available.filter { $0.group == group }
            if !options.isEmpty {
                let selectedID = assigned.first { $0.group == group }?.id
                Picker(
                    title(group),
                    selection: binding(group: group, selectedID: selectedID)
                ) {
                    Text("\(title(group)): None").tag(UUID?.none)
                    ForEach(options, id: \.id) { label in
                        Text(label.name).tag(UUID?.some(label.id))
                    }
                }
                .pickerStyle(.menu)
                .tint(NexusColor.Text.primary)
            }
        }
    }

    @ViewBuilder
    private var freeCreator: some View {
        let freeOptions = available.filter { label in
            label.group == .free && !assigned.contains { $0.id == label.id }
        }
        if !freeOptions.isEmpty {
            FlowLabels.tappable(labels: freeOptions, onTap: assign)
        }
        HStack(spacing: 8) {
            #if os(iOS)
            TextField("New label", text: $draft)
                .textInputAutocapitalization(.never)
            #else
            TextField("New label", text: $draft)
            #endif
            Button("Add") { createAndAssign() }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func binding(group: LabelGroup, selectedID: UUID?) -> Binding<UUID?> {
        Binding(
            get: { selectedID },
            set: { newID in
                if let newID, let label = available.first(where: { $0.id == newID }) {
                    assign(label)
                } else if let current = assigned.first(where: { $0.group == group }) {
                    remove(current)
                }
            }
        )
    }

    private func title(_ group: LabelGroup) -> String {
        switch group {
        case .domain: return "Domain"
        case .gate: return "Gate"
        case .free: return "Labels"
        }
    }

    @MainActor
    private func load() {
        let repository = LabelRepository(context: modelContext)
        do {
            assigned = try repository.labels(for: endpoint)
            available = try repository.allActive()
        } catch {
            assigned = []
            available = []
        }
    }

    @MainActor
    private func assign(_ label: TaskLabel) {
        let repository = LabelRepository(context: modelContext)
        do {
            try repository.assign(label, to: endpoint)
        } catch {
            // Best-effort; reload reflects the persisted truth either way.
        }
        load()
    }

    @MainActor
    private func remove(_ label: TaskLabel) {
        let repository = LabelRepository(context: modelContext)
        do {
            try repository.remove(label, from: endpoint)
        } catch {
            // Best-effort; reload reflects the persisted truth either way.
        }
        load()
    }

    @MainActor
    private func createAndAssign() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let repository = LabelRepository(context: modelContext)
        do {
            let existing = try repository.allActive()
                .first { $0.name.lowercased() == name.lowercased() }
            let label = try existing ?? repository.create(name: name, group: .free)
            try repository.assign(label, to: endpoint)
            draft = ""
            load()
        } catch {
            load()
        }
    }
}
