import NexusCore
import NexusUI
import SwiftUI

/// Milestone node diameter — spec §Milestones & Roadmap shows ~22 pt circles
/// (between the 18–22 pt avatar guidance and the 14 pt task checkbox).
private let nodeSize: CGFloat = 22
/// Connector segment length between nodes; wide enough for the 5-stop
/// reference roadmap to breathe, short enough to avoid hugging the edges.
private let connectorWidth: CGFloat = 72
/// Label column under each node (keeps long section names from re-flowing
/// the timeline geometry).
private let labelWidth: CGFloat = 120

/// Milestones & Roadmap strip (spec §Milestones & Roadmap): the project's
/// sections as a horizontal timeline via `ProjectExecutionModel.milestones` —
/// completed = green check node, in-progress = primary glow node, upcoming =
/// neutral stroke; connector segments accent the active stretch.
struct MilestoneStrip: View {

    let milestones: [ProjectExecutionModel.Milestone]

    var body: some View {
        LiquidGlassCard("Milestones & Roadmap") {
            if milestones.isEmpty {
                LiquidEmptyState(
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    message: "No sections yet — they appear here as roadmap milestones."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                            milestoneNode(milestone)
                            if index < milestones.count - 1 {
                                connector(after: milestone, before: milestones[index + 1])
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.xs)
                }
            }
        }
    }

    // MARK: - Node

    private func milestoneNode(_ milestone: ProjectExecutionModel.Milestone) -> some View {
        VStack(spacing: DS.Space.xs) {
            node(for: milestone.state)

            VStack(spacing: 2) {
                Text(milestone.title)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(titleColor(for: milestone.state))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(stateLabel(for: milestone.state))
                    .font(DS.FontToken.caption)
                    .foregroundStyle(captionColor(for: milestone.state))
            }
            .frame(width: labelWidth)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(milestone.title), \(stateLabel(for: milestone.state))")
    }

    @ViewBuilder
    private func node(for state: ProjectExecutionModel.MilestoneState) -> some View {
        switch state {
        case .completed:
            ZStack {
                Circle()
                    // 18% green wash inside a solid green ring — the LiquidPill
                    // tint formula (14–28%) applied to a roadmap node.
                    .fill(DS.ColorToken.accentGreen.opacity(0.18))
                Circle()
                    .stroke(DS.ColorToken.accentGreen, lineWidth: 1.5)
                Image(systemName: "checkmark")
                    // 9 pt check fits the 22 pt node; no DS token at this scale.
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.ColorToken.accentGreen)
            }
            .frame(width: nodeSize, height: nodeSize)
        case .inProgress:
            ZStack {
                Circle()
                    .fill(DS.ColorToken.accentPrimary.opacity(0.28))
                Circle()
                    .stroke(DS.ColorToken.accentPrimary, lineWidth: 1.5)
                Circle()
                    .fill(DS.ColorToken.accentPrimaryHover)
                    .frame(width: 8, height: 8)
            }
            .frame(width: nodeSize, height: nodeSize)
            // Spec: "active node primary purple/blue glow" — same 35% glow
            // recipe LiquidCircularProgress uses for its active ring.
            .shadow(color: DS.ColorToken.accentPrimary.opacity(0.35), radius: 8)
        case .upcoming:
            Circle()
                .stroke(DS.ColorToken.strokeStrong, lineWidth: 1.5)
                .frame(width: nodeSize, height: nodeSize)
        }
    }

    // MARK: - Connector

    /// Spec: "line between milestones subtle, active segment accent" — the
    /// segment feeding the in-progress node carries the primary accent, the
    /// stretch between completed nodes reads as a faded done-trail, the rest
    /// stay hairline-subtle.
    private func connector(
        after lhs: ProjectExecutionModel.Milestone,
        before rhs: ProjectExecutionModel.Milestone
    ) -> some View {
        Rectangle()
            .fill(connectorColor(after: lhs.state, before: rhs.state))
            .frame(width: connectorWidth, height: 2)
            // Centers the 2 pt line on the 22 pt node row.
            .padding(.top, nodeSize / 2 - 1)
            .accessibilityHidden(true)
    }

    private func connectorColor(
        after lhs: ProjectExecutionModel.MilestoneState,
        before rhs: ProjectExecutionModel.MilestoneState
    ) -> Color {
        if rhs == .inProgress { return DS.ColorToken.accentPrimary }
        if lhs == .completed && rhs == .completed { return DS.ColorToken.accentGreen.opacity(0.4) }
        return DS.ColorToken.strokeDefault
    }

    // MARK: - Labels

    private func stateLabel(for state: ProjectExecutionModel.MilestoneState) -> String {
        switch state {
        case .completed: return "Completed"
        case .inProgress: return "In Progress"
        case .upcoming: return "Upcoming"
        }
    }

    private func titleColor(for state: ProjectExecutionModel.MilestoneState) -> Color {
        switch state {
        case .completed: return DS.ColorToken.textSecondary
        case .inProgress: return DS.ColorToken.textPrimary
        case .upcoming: return DS.ColorToken.textTertiary
        }
    }

    private func captionColor(for state: ProjectExecutionModel.MilestoneState) -> Color {
        switch state {
        case .completed: return DS.ColorToken.accentGreen
        case .inProgress: return DS.ColorToken.accentPrimaryHover
        case .upcoming: return DS.ColorToken.textMuted
        }
    }
}
