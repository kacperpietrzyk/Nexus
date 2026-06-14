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

        VStack(alignment: .leading, spacing: DS.Space.l) {
            statRow(stats)
            MilestoneStrip(milestones: milestones)
            cardGrid(health: health, progress: progress, risks: risks, tasks: tasks, activity: activity)
        }
    }

    private func statRow(_ stats: ProjectExecutionModel.ProjectStats) -> some View {
        HStack(spacing: DS.Space.m) {
            ProjectStatTile(value: "\(Int((stats.progress * 100).rounded()))%", label: "Progress")
            ProjectStatTile(value: "\(stats.open)", label: "Open")
            ProjectStatTile(value: "\(stats.done)", label: "Done")
            ProjectStatTile(value: "\(stats.overdue)", label: "Overdue")
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
        let left = VStack(spacing: DS.Space.l) {
            ProjectHealthCard(health: health, progress: progress, detail: detail)
            DeliveryRiskCard(risks: risks, tasks: tasks, onOpenTask: onOpenTask)
        }
        let right = VStack(spacing: DS.Space.l) {
            RecentActivityCard(activity: activity)
            AINextStepsCard()
        }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DS.Space.l) {
                left.frame(maxWidth: .infinity, alignment: .top)
                right.frame(maxWidth: .infinity, alignment: .top)
            }
            VStack(spacing: DS.Space.l) {
                left
                right
            }
        }
    }
}

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
        .liquidGlass(.card, radius: DS.Radius.m)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
