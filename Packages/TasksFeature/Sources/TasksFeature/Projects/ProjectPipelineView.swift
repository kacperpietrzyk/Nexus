import NexusCore
import NexusUI
import SwiftUI

/// Horizontally-scrolling kanban-style lane view that groups stage-bearing
/// projects by their current pipeline stage (spec §9).
///
/// When the project list contains more than one stage-bearing type, a
/// `LiquidSegmentedControl` type selector renders above the lanes; it defaults
/// to the type with the most projects (ties broken by `ProjectType.allCases`
/// order).  Drag a project card onto a lane header to move it to that stage.
struct ProjectPipelineView: View {

    let projects: [Project]
    let onOpen: (Project) -> Void
    let onSetStage: (Project, ProjectStage?) -> Void

    /// Nil until the user taps a different type; the effective type falls back
    /// to the dominant type (most projects) so no state-write is needed in body.
    @State private var selectedType: ProjectType?

    var body: some View {
        if lanes.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if stageBearingTypes.count > 1 {
                    typeSelector
                        .padding(.horizontal, DS.Space.m)
                        .padding(.top, DS.Space.m)
                }
                laneScroll
            }
        }
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        LiquidSegmentedControl(
            options: stageBearingTypes.map { .init($0, label: $0.displayName) },
            selection: Binding(
                get: { effectiveType },
                set: { selectedType = $0 }
            )
        )
    }

    // MARK: - Lane scroll

    private var laneScroll: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                ForEach(lanes, id: \.stageID) { lane in
                    laneColumn(lane)
                }
            }
            .padding(DS.Space.m)
        }
    }

    private func laneColumn(_ lane: Lane) -> some View {
        LiquidGlassCard(lane.title) {
            laneContent(lane)
        }
        .frame(width: 220)
        .dropDestination(for: String.self) { items, _ in
            guard
                let idString = items.first,
                let id = UUID(uuidString: idString),
                let project = projects.first(where: { $0.id == id })
            else { return false }
            onSetStage(project, lane.stage)
            return true
        }
    }

    private func laneContent(_ lane: Lane) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(lane.projects, id: \.id) { project in
                projectCard(project)
            }
            if lane.projects.isEmpty {
                Text("—")
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        Button {
            onOpen(project)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(project.name)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                if let vendor = project.vendor {
                    Text(vendor)
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.name)
        .draggable(project.id.uuidString)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        LiquidEmptyState(
            systemImage: "arrow.left.arrow.right",
            message: "No pipeline projects yet — set a Sales, Implementation, Audit, or Internal type to track stages here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lane model

    private struct Lane {
        /// Stable identity: "nil" maps to the empty-string sentinel so
        /// `ForEach(id:)` gets a non-optional Hashable key.
        let stageID: String
        let title: String
        let projects: [Project]
        let stage: ProjectStage?

        init(stage: ProjectStage?, title: String, projects: [Project]) {
            self.stageID = stage?.rawValue ?? ""
            self.title = title
            self.projects = projects
            self.stage = stage
        }
    }

    // MARK: - Derived state

    /// All distinct stage-bearing types present in `projects`, ordered by
    /// `ProjectType.allCases` for a stable, predictable sequence.
    private var stageBearingTypes: [ProjectType] {
        let present = Set(projects.filter { !$0.type.stages.isEmpty }.map(\.type))
        return ProjectType.allCases.filter { present.contains($0) }
    }

    /// The type with the most projects; ties broken by `allCases` order.
    private var dominantType: ProjectType? {
        stageBearingTypes.max(by: { a, b in
            projects.filter { $0.type == a }.count
                < projects.filter { $0.type == b }.count
        })
    }

    /// The type actually used for lane computation — user override or dominant.
    private var effectiveType: ProjectType {
        selectedType ?? dominantType ?? .generic
    }

    private var lanes: [Lane] {
        guard !stageBearingTypes.isEmpty else { return [] }
        let inType = projects.filter { $0.type == effectiveType }
        var result: [Lane] = [
            Lane(stage: nil, title: "No stage", projects: inType.filter { $0.stage == nil })
        ]
        for stage in effectiveType.stages {
            result.append(
                Lane(stage: stage, title: stage.displayName, projects: inType.filter { $0.stage == stage })
            )
        }
        return result
    }
}
