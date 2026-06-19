import NexusCore
import NexusUI
import SwiftUI

/// The Liquid Projects **Overview** tab: a real project dashboard — KPI stat
/// row, the milestone/roadmap strip, and a two-column grid of Health / Delivery
/// Risk / Recent Activity / AI Next Steps. Replaces the old stacked
/// "milestones + board + table" overview and the separate right inspector; all
/// content is full-width in the main column. Reads the shared
/// `LiquidProjectsModel`, with the same reference-mode snapshot branch the rest
/// of the screen uses.
struct ProjectOverview: View {
    let model: LiquidProjectsModel
    let onOpenTask: (TaskItem) -> Void

    @Environment(\.modelContext) private var modelContext

    private var reference: LiquidProjectsReferenceData.Snapshot? {
        LiquidReferenceMode.isEnabled ? LiquidProjectsReferenceData.snapshot(now: .now) : nil
    }

    var body: some View {
        let tasks = reference?.tasks ?? model.tasks
        let progress = reference?.progress ?? model.progress
        let health = reference?.health ?? model.health
        let risks = reference?.risks ?? model.risks
        let activity = reference?.activity ?? model.activity
        let milestones = reference?.milestones ?? model.milestones
        let stats = ProjectExecutionModel.stats(tasks: tasks, now: .now)
        let projectType = model.selectedProject?.type ?? .generic

        VStack(alignment: .leading, spacing: DS.Space.l) {
            statRow(stats, type: projectType, project: model.selectedProject)
            MilestoneStrip(milestones: milestones)
            cardGrid(health: health, progress: progress, risks: risks, tasks: tasks, activity: activity)
        }
    }

    // Progress % is intentionally omitted here — it already reads on the
    // header bar and the health gauge; a third copy was redundant.
    private func statRow(
        _ stats: ProjectExecutionModel.ProjectStats,
        type: ProjectType,
        project: Project?
    ) -> some View {
        HStack(spacing: DS.Space.m) {
            ForEach(ProjectExecutionModel.kpiLabels(for: type), id: \.self) { label in
                ProjectStatTile(value: statValue(label, stats), label: label)
            }
            if let tile = typeExtraTile(type: type, project: project) {
                ProjectStatTile(value: tile.value, label: tile.label)
            }
        }
    }

    private func statValue(_ label: String, _ stats: ProjectExecutionModel.ProjectStats) -> String {
        switch label {
        case "Open": return "\(stats.open)"
        case "Done": return "\(stats.done)"
        case "Overdue": return "\(stats.overdue)"
        default: return "—"
        }
    }

    @MainActor private func typeExtraTile(
        type: ProjectType,
        project: Project?
    ) -> (value: String, label: String)? {
        guard let project else { return nil }
        switch type {
        case .sales:
            if let deal = project.customFields["dealValue"] { return (deal, "Deal") }
            return nil
        case .implementation:
            let dates =
                (try? ProjectKeyDateRepository(context: modelContext).list(projectID: project.id)) ?? []
            if let poDate = dates.first(where: { $0.anchorKey == "PO" }) {
                return (
                    "\(ProjectExecutionModel.daysRemaining(to: poDate.date, from: .now))d",
                    "To PO"
                )
            }
            return nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private func cardGrid(
        health: ProjectExecutionModel.ProjectHealth,
        progress: Double,
        risks: [ProjectExecutionModel.ProjectRisk],
        tasks: [TaskItem],
        activity: [ProjectExecutionModel.ActivityEntry]
    ) -> some View {

        let detail =
            "\(tasks.count(where: { $0.status == .done })) done"
            + " · \(tasks.count(where: { $0.status != .done })) open"
        let hasDatedOpenTasks = tasks.contains {
            $0.status != .done && ($0.dueAt != nil || $0.deadlineAt != nil)
        }
        let healthCard = ProjectHealthCard(
            health: health,
            progress: progress,
            detail: detail,
            hasDatedOpenTasks: hasDatedOpenTasks
        )
        let empty = risks.isEmpty && activity.isEmpty

        if empty {
            sparseCardColumn(healthCard: healthCard)
        } else {
            denseCardGrid(
                healthCard: healthCard,
                risks: risks,
                tasks: tasks,
                activity: activity
            )
        }
    }

    /// Two-column grid used when there is real content on both sides.
    ///
    /// `minWidth` gives the two-column row a definite minimum so `ViewThatFits`
    /// falls back to the stacked layout once the available width can't host two
    /// readable columns (flexible cards otherwise always "fit" by shrinking, and
    /// the second column would clip off-window).
    @ViewBuilder
    private func denseCardGrid(
        healthCard: ProjectHealthCard,
        risks: [ProjectExecutionModel.ProjectRisk],
        tasks: [TaskItem],
        activity: [ProjectExecutionModel.ActivityEntry]
    ) -> some View {
        let left = VStack(spacing: DS.Space.l) {
            healthCard
            DeliveryRiskCard(risks: risks, tasks: tasks, onOpenTask: onOpenTask)
        }
        let right = VStack(spacing: DS.Space.l) {
            RecentActivityCard(activity: activity)
            AINextStepsCard()
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Space.l) {
                left.frame(minWidth: overviewColumnMinWidth, maxWidth: .infinity, alignment: .top)
                right.frame(minWidth: overviewColumnMinWidth, maxWidth: .infinity, alignment: .top)
            }
            VStack(spacing: DS.Space.l) {
                left
                right
            }
        }
    }

    /// Single-column layout for sparse projects: Health + AI, with the empty
    /// Delivery Risk / Recent Activity pair collapsed into one informative row.
    @ViewBuilder
    private func sparseCardColumn(
        healthCard: ProjectHealthCard
    ) -> some View {
        VStack(spacing: DS.Space.l) {
            healthCard
            noRisksActivityRow
            AINextStepsCard()
        }
    }

    /// Collapsed informative row shown when both risks and activity are empty.
    private var noRisksActivityRow: some View {
        LiquidGlassCard("Delivery Risk & Activity") {
            LiquidEmptyState(
                systemImage: "checkmark.shield",
                message: "No risks or recent activity yet."
            )
        }
    }
}

/// Minimum width per Overview dashboard column; below ~2× this the two-column
/// grid collapses to a single stacked column (see `cardGrid`).
private let overviewColumnMinWidth: CGFloat = 330

private struct ProjectStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(value)
                .font(DS.FontToken.title.monospacedDigit())
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(label)
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .liquidLightCard(cornerRadius: DS.Radius.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
