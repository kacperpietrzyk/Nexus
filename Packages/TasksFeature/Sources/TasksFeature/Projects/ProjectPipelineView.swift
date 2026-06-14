import NexusCore
import NexusUI
import SwiftUI

/// Horizontally-scrolling kanban-style lane view that groups stage-bearing
/// projects by their current pipeline stage (spec §9).
///
/// v1 limitation: when the project list contains more than one stage-bearing
/// type (e.g. `.sales` and `.internalDev`), only the dominant type — the type
/// of the first stage-bearing project — is rendered. A future task can add a
/// type-selector above the lanes to let the user switch between them.
/// `.generic` projects have no stages and are excluded entirely.
struct ProjectPipelineView: View {

    let projects: [Project]
    let onOpen: (Project) -> Void

    var body: some View {
        if lanes.isEmpty {
            emptyState
        } else {
            laneScroll
        }
    }

    /// Shown when no project carries a stage preset (e.g. all projects are
    /// `.generic`), so there are no lanes to render.
    private var emptyState: some View {
        LiquidEmptyState(
            systemImage: "arrow.left.arrow.right",
            message: "No pipeline projects yet — set a Sales, Implementation, Audit, or Internal type to track stages here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var laneScroll: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                ForEach(lanes, id: \.stageID) { lane in
                    LiquidGlassCard(lane.title) {
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(lane.projects, id: \.id) { project in
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
                            }
                            if lane.projects.isEmpty {
                                Text("—")
                                    .foregroundStyle(DS.ColorToken.textTertiary)
                            }
                        }
                    }
                    .frame(width: 220)
                }
            }
            .padding(DS.Space.m)
        }
    }

    // MARK: - Lane model

    private struct Lane {
        /// Stable identity: "nil" maps to the empty-string sentinel so
        /// `ForEach(id:)` gets a non-optional Hashable key.
        let stageID: String
        let title: String
        let projects: [Project]

        init(stage: ProjectStage?, title: String, projects: [Project]) {
            self.stageID = stage?.rawValue ?? ""
            self.title = title
            self.projects = projects
        }
    }

    private var lanes: [Lane] {
        // Only stage-bearing projects participate in the pipeline.
        let typed = projects.filter { !$0.type.stages.isEmpty }
        // v1: pick the type of the first stage-bearing project as the
        // dominant type. Mixed-type lists are handled in a future iteration.
        guard let dominantType = typed.first?.type else { return [] }
        let inType = typed.filter { $0.type == dominantType }

        var result: [Lane] = [
            Lane(stage: nil, title: "No stage", projects: inType.filter { $0.stage == nil })
        ]
        for stage in dominantType.stages {
            result.append(
                Lane(stage: stage, title: stage.displayName, projects: inType.filter { $0.stage == stage })
            )
        }
        return result
    }
}
