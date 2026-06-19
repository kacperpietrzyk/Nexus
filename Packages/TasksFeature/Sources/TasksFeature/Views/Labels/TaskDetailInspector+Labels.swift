import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The Labels section on a task inspector (Projects tier, spec §3 / §7). Assign
/// and remove structural labels through `LabelRepository`, which enforces
/// single-select for `domain`/`gate` (invariant I5) — the picker reflects that by
/// presenting those groups as a single choice and `free` labels as an additive
/// multi-select. System labels are non-deletable (shown without a remove
/// affordance). Achromatic glyphs per LabKit (`LabelChipRow`).
///
/// Labels hang off the `Link` graph (`LinkKind.labeled`), so the repo is built
/// ad-hoc from `modelContext` (the established `LinkRepository(context:)`
/// convention in this inspector) rather than via an environment key.
extension TaskDetailInspector {

    var classificationCard: some View {
        inspectorCard("Classification") {
            tagsSection
            assignedLabelsSection
            labelGroupPickers
            freeLabelCreator
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            TagsEditor(tags: $task.tags) { save() }
        }
    }

    // MARK: - Assigned

    @ViewBuilder
    private var assignedLabelsSection: some View {
        if assignedLabels.isEmpty {
            Text("No labels")
                .font(.caption)
                .foregroundStyle(NexusColor.Text.tertiary)
        } else {
            FlowLabels.removable(labels: assignedLabels) { label in
                removeLabel(label)
            }
        }
    }

    // MARK: - Single-select group pickers (domain / gate)

    /// One menu per single-select group (`domain`, `gate`). Picking a label
    /// assigns it (the repo clears any prior label of the same group, I5); the
    /// current selection is shown as the menu's value.
    @ViewBuilder
    private var labelGroupPickers: some View {
        ForEach([LabelGroup.domain, LabelGroup.gate], id: \.self) { group in
            let options = availableLabels.filter { $0.group == group }
            if !options.isEmpty {
                groupPicker(group: group, options: options)
            }
        }
    }

    private func groupPicker(group: LabelGroup, options: [TaskLabel]) -> some View {
        let selectedID = assignedLabels.first { $0.group == group }?.id
        return VStack(alignment: .leading, spacing: 6) {
            Text(groupTitle(group).uppercased())
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            NexusSelect(
                selection: groupBinding(group: group, selectedID: selectedID),
                options: [UUID?.none] + options.map { Optional($0.id) },
                label: { id in
                    guard let id, let label = options.first(where: { $0.id == id }) else { return "None" }
                    return label.name
                },
                accessibilityLabel: groupTitle(group)
            )
            if let caption = groupCaption(group) {
                Text(caption)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }

    private func groupBinding(group: LabelGroup, selectedID: UUID?) -> Binding<UUID?> {
        Binding(
            get: { selectedID },
            set: { newID in
                if let newID, let label = availableLabels.first(where: { $0.id == newID }) {
                    assignLabel(label)
                } else if let current = assignedLabels.first(where: { $0.group == group }) {
                    removeLabel(current)
                }
            }
        )
    }

    private func groupTitle(_ group: LabelGroup) -> String {
        switch group {
        case .domain: return "Type"
        case .gate: return "Decision"
        case .free: return "Labels"
        }
    }

    private func groupCaption(_ group: LabelGroup) -> String? {
        switch group {
        case .domain: return "Feature / bug / infra / security — drives agent suggestion."
        case .gate: return "Needs decision / decided — gates workflow."
        case .free: return nil
        }
    }

    // MARK: - Free labels (multi-select + create)

    @ViewBuilder
    private var freeLabelCreator: some View {
        let freeOptions = availableLabels.filter { label in
            label.group == .free && !assignedLabels.contains { $0.id == label.id }
        }
        VStack(alignment: .leading, spacing: 8) {
            if !freeOptions.isEmpty {
                FlowLabels.tappable(labels: freeOptions, onTap: assignLabel)
            }
            HStack(spacing: 8) {
                labelDraftField
                Button("Add") { createAndAssignFreeLabel() }
                    .disabled(newLabelDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var labelDraftField: some View {
        #if os(iOS)
        NexusTextField("New label", text: $newLabelDraft)
            .textInputAutocapitalization(.never)
        #else
        NexusTextField("New label", text: $newLabelDraft)
        #endif
    }

    // MARK: - Data

    private var labelEndpoint: (LabelEndpointKind, UUID) { (.task, task.id) }

    @MainActor
    func loadLabels() {
        let repository = LabelRepository(context: modelContext)
        do {
            assignedLabels = try repository.labels(for: labelEndpoint)
            availableLabels = try repository.allActive()
        } catch {
            assignedLabels = []
            availableLabels = []
        }
    }

    @MainActor
    private func assignLabel(_ label: TaskLabel) {
        let repository = LabelRepository(context: modelContext)
        do {
            try repository.assign(label, to: labelEndpoint)
            loadLabels()
        } catch {
            loadLabels()
        }
    }

    @MainActor
    private func removeLabel(_ label: TaskLabel) {
        let repository = LabelRepository(context: modelContext)
        do {
            try repository.remove(label, from: labelEndpoint)
            loadLabels()
        } catch {
            loadLabels()
        }
    }

    @MainActor
    private func createAndAssignFreeLabel() {
        let name = newLabelDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let repository = LabelRepository(context: modelContext)
        do {
            // Reuse an existing same-named label (case-insensitive) rather than
            // creating a duplicate row, then assign it to this task.
            let existing = try repository.allActive()
                .first { $0.name.lowercased() == name.lowercased() }
            let label = try existing ?? repository.create(name: name, group: .free)
            try repository.assign(label, to: labelEndpoint)
            newLabelDraft = ""
            loadLabels()
        } catch {
            loadLabels()
        }
    }
}

/// A wrapping row of label chips. Tapping (when an `action` is supplied) invokes
/// it; otherwise the per-chip `onRemove` (driven by `LabelChipRow`) handles
/// removal. Uses a simple `HStack`-in-`ScrollView` to stay layout-cheap.
struct FlowLabels: View {
    let labels: [TaskLabel]
    var action: ((TaskLabel) -> Void)?
    var onRemove: ((TaskLabel) -> Void)?

    private init(labels: [TaskLabel], action: ((TaskLabel) -> Void)?, onRemove: ((TaskLabel) -> Void)?) {
        self.labels = labels
        self.action = action
        self.onRemove = onRemove
    }

    /// Tappable chips (an "add" picker): tapping a chip invokes `onTap`.
    static func tappable(labels: [TaskLabel], onTap: @escaping (TaskLabel) -> Void) -> FlowLabels {
        FlowLabels(labels: labels, action: onTap, onRemove: nil)
    }

    /// Removable chips (assigned labels): the per-chip `xmark` invokes `onRemove`.
    static func removable(labels: [TaskLabel], onRemove: @escaping (TaskLabel) -> Void) -> FlowLabels {
        FlowLabels(labels: labels, action: nil, onRemove: onRemove)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.id) { label in
                    chip(for: label)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func chip(for label: TaskLabel) -> some View {
        if let action {
            Button {
                action(label)
            } label: {
                LabelChipRow(label: label)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add label \(label.name)")
        } else {
            LabelChipRow(label: label, onRemove: { onRemove?(label) })
        }
    }
}
