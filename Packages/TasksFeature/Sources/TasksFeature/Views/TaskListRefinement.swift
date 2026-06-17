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

/// Memoizes the labeled-task-id resolution so a reload that does NOT change the
/// selected label (a `now` tick, a store-change refresh, an agent-axis flip)
/// reuses the cached id-set instead of re-querying `LinkRepository.backlinks`.
/// The resolved set is purely a function of `labelID`, so caching on it is
/// pixel-identical: the same ids feed `keeps(_:)` either way. A `nil` `labelID`
/// resolves to `nil` (no label constraint) and is cached the same way.
struct LabeledTaskIDCache {
    private var cachedLabelID: UUID??
    private var cachedIDs: Set<UUID>?

    /// Returns the id-set for `labelID`, re-running `fetch` only when `labelID`
    /// differs from the last resolved value. `fetch` is the `LinkRepository`
    /// backlink walk (`TaskListRefinement.labeledTaskIDs`).
    mutating func ids(for labelID: UUID?, fetch: (UUID?) -> Set<UUID>?) -> Set<UUID>? {
        if let cachedLabelID, cachedLabelID == labelID {
            return cachedIDs
        }
        let resolved = fetch(labelID)
        cachedLabelID = labelID
        cachedIDs = resolved
        return resolved
    }

    /// Drops the cached resolution so the next `ids(for:)` re-queries. Called on a
    /// store change: the label→task graph can mutate (CloudKit sync, agent tool,
    /// Task Assist) WITHOUT `labelID` changing, so caching on `labelID` alone would
    /// return a stale set. Mirrors the FIX-1 `markDirty()` invalidation.
    mutating func invalidate() {
        cachedLabelID = nil
        cachedIDs = nil
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
    /// Liquid re-skin (container level): the list container + rows are
    /// transparent so the shell paints the canvas behind them — on macOS the
    /// shell glass panel, on iOS the aurora + a light-glass list panel (the touch
    /// Liquid pass, mirroring `LiquidTodayScreen`). An opaque `Background.base`
    /// here read as a black slab over both. (Lives here, not in TaskListView.swift,
    /// for that file's `file_length` headroom.)
    var containerBackground: Color {
        Color.clear
    }

    func applyRefinement() {
        guard refinement.isActive else { return }
        // Memoized label resolution: re-query LinkRepository only when the
        // selected label changes (FIX 3a). Same id-set otherwise → identical filter.
        let labeledIDs = labeledTaskIDCache.ids(for: refinement.labelID) { labelID in
            guard labelID != nil else { return nil }
            return refinement.labeledTaskIDs(in: modelContext)
        }
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
/// menu as Liquid glass chips; a single "Clear" affordance when active.
struct TaskListFilterBar: View {
    @Binding var refinement: TaskListRefinement
    let availableLabels: [TaskLabel]

    var body: some View {
        if !availableLabels.isEmpty {
            HStack(spacing: DS.Space.s) {
                labelMenu
                agentMenu
                if refinement.isActive {
                    Button("Clear") { refinement = TaskListRefinement() }
                        .buttonStyle(.plain)
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .accessibilityLabel("Clear filters")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.s)
            .background(barBackground)
            .tint(DS.ColorToken.textPrimary)
        }
    }

    /// Liquid re-skin (container level): transparent on macOS so the bar sits
    /// on the shell's glass content panel (the opaque base read as a black
    /// strip over glass); iOS keeps the opaque Linear base under its own shell.
    private var barBackground: Color {
        #if os(macOS)
        return Color.clear
        #else
        return NexusColor.Background.base
        #endif
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
            LiquidFilterChip(
                systemImage: "tag",
                text: selectedLabelName ?? "Label",
                isActive: refinement.labelID != nil
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var agentMenu: some View {
        Menu {
            Button("Any agent") { refinement.agent = nil }
            ForEach(AgentAssignee.allCases, id: \.self) { agent in
                Button(agentName(agent)) { refinement.agent = agent }
            }
        } label: {
            LiquidFilterChip(
                systemImage: "person",
                text: refinement.agent.map(agentName) ?? "Agent",
                isActive: refinement.agent != nil
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
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

/// Liquid menu chip for the filter bar: glass capsule with a hairline rim;
/// an active filter brightens to a primary-accent tint (hover/selected may
/// not rely on color alone — the fill change pairs with the stroke change,
/// 01_FOUNDATIONS §Dostępność).
private struct LiquidFilterChip: View {
    let systemImage: String
    let text: String
    let isActive: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(DS.FontToken.caption)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textMuted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(isActive ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
        .padding(.horizontal, DS.Space.s)
        .frame(height: 22)
        .background {
            Capsule(style: .continuous)
                .fill(chipFill)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(chipStroke, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule(style: .continuous))
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }

    private var chipFill: Color {
        if isActive {
            // 14% accent fill — same passive-pill calibration as LiquidPill.
            return DS.ColorToken.accentPrimary.opacity(0.14)
        }
        return hovering ? DS.ColorToken.glassCardHover : DS.ColorToken.glassSoft
    }

    private var chipStroke: Color {
        if isActive {
            // 22% accent rim — same calibration as LiquidPill's border.
            return DS.ColorToken.accentPrimary.opacity(0.22)
        }
        return hovering ? DS.ColorToken.strokeStrong : DS.ColorToken.strokeHairline
    }
}
