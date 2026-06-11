import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Sidebar ordering + badge derivation, extracted pure so it is testable
/// without driving SwiftUI (the `TaskListEmptyState.resolve` precedent).
enum CyclesSidebarModel {
    /// Live, not-completed cycles: active first, then ascending `startAt`,
    /// UUID tie-break for determinism.
    @MainActor
    static func displayOrder(_ cycles: [Cycle]) -> [Cycle] {
        cycles
            .filter { $0.deletedAt == nil && $0.status != .completed }
            .sorted { lhs, rhs in
                let lhsRank = lhs.status == .active ? 0 : 1
                let rhsRank = rhs.status == .active ? 0 : 1
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// "Current" = active AND containing now; "Next" = the earliest upcoming
    /// cycle starting after now. An overrun active cycle gets no badge — the
    /// planner surfaces its end-of-cycle prompt instead.
    @MainActor
    static func badge(for cycle: Cycle, in ordered: [Cycle], now: Date) -> String? {
        if cycle.status == .active && cycle.startAt <= now && now <= cycle.endAt {
            return "Current"
        }
        let next = ordered.first { $0.status == .upcoming && $0.startAt > now }
        return next?.id == cycle.id ? "Next" : nil
    }
}

public struct CyclesSidebarSection: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Cycle.startAt) private var queriedCycles: [Cycle]

    @Binding private var selection: TaskFilter
    private let onSelect: () -> Void

    @State private var editorMode: CycleEditorMode?
    @State private var planningCycle: Cycle?
    @State private var error: String?

    public init(selection: Binding<TaskFilter>, onSelect: @escaping () -> Void = {}) {
        self._selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if cycles.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(cycles) { cycle in
                        row(cycle)
                    }
                }
            }

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
            }
        }
        .sheet(item: $editorMode) { mode in
            CycleEditorSheet(cycle: mode.cycle)
        }
        .sheet(item: $planningCycle) { cycle in
            CyclePlanningView(cycle: cycle)
        }
    }

    private var cycles: [Cycle] {
        CyclesSidebarModel.displayOrder(Array(queriedCycles))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cycles")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            Spacer()

            NexusButton(
                variant: .ghost, size: .iconSm, action: { editorMode = .create },
                label: {
                    Image(systemName: "plus")
                }
            )
            .help("Create cycle")
            .accessibilityLabel("Create cycle")
        }
    }

    private var emptyState: some View {
        Button {
            editorMode = .create
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Add cycle")
                Spacer()
            }
            .nexusType(.bodySmall)
            .foregroundStyle(NexusColor.Text.tertiary)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .nexusRowHover()
    }

    private func row(_ cycle: Cycle) -> some View {
        CycleSidebarRow(
            title: cycle.name,
            badge: CyclesSidebarModel.badge(for: cycle, in: cycles, now: .now),
            isSelected: selection == .cycle(cycle.id),
            action: {
                selection = .cycle(cycle.id)
                onSelect()
            }
        )
        .contextMenu {
            Button("Plan Cycle…") { planningCycle = cycle }
            if cycle.status == .upcoming {
                Button("Start Cycle") { setStatus(.active, on: cycle) }
            }
            if cycle.status == .active {
                Button("Complete Cycle") { complete(cycle) }
            }
            Button("Edit Cycle…") { editorMode = .edit(cycle) }
            Divider()
            Button("Delete Cycle", role: .destructive) { delete(cycle) }
        }
    }

    @MainActor
    private func setStatus(_ status: CycleStatus, on cycle: Cycle) {
        do {
            try CycleRepository(context: modelContext).setStatus(status, on: cycle)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func complete(_ cycle: Cycle) {
        setStatus(.completed, on: cycle)
        resetSelectionIfNeeded(for: cycle)
    }

    @MainActor
    private func delete(_ cycle: Cycle) {
        do {
            try CycleRepository(context: modelContext).softDelete(cycle)
            resetSelectionIfNeeded(for: cycle)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func resetSelectionIfNeeded(for cycle: Cycle) {
        if selection == .cycle(cycle.id) {
            selection = .upcoming
            onSelect()
        }
    }
}

private struct CycleSidebarRow: View {
    let title: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                    .frame(width: 16)

                Text(title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let badge {
                    Text(badge)
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(NexusColor.Background.control, in: Capsule())
                }
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                        .fill(NexusColor.Background.controlHover)
                }
            }
        }
        .buttonStyle(.plain)
        .nexusRowHover()
        .accessibilityLabel(title)
    }
}

private enum CycleEditorMode: Identifiable {
    case create
    case edit(Cycle)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let cycle):
            return cycle.id.uuidString
        }
    }

    var cycle: Cycle? {
        switch self {
        case .create:
            return nil
        case .edit(let cycle):
            return cycle
        }
    }
}
