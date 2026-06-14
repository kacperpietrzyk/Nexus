import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/03_COMPONENTS.md` §CircularProgress: project health gauge 62–70 pt.
private let healthGaugeSize: CGFloat = 66

// MARK: - Health helpers (file-scope, shared by ProjectHealthCard and future callers)

func projectHealthColor(_ health: ProjectExecutionModel.ProjectHealth) -> Color {
    switch health {
    case .onTrack: return DS.ColorToken.statusSuccess
    case .atRisk: return DS.ColorToken.statusWarning
    case .offTrack: return DS.ColorToken.statusDanger
    }
}

func projectHealthLabel(_ health: ProjectExecutionModel.ProjectHealth) -> String {
    switch health {
    case .onTrack: return "On Track"
    case .atRisk: return "At Risk"
    case .offTrack: return "Off Track"
    }
}

// MARK: - ProjectHealthCard

/// Standalone "Project Health" card for the Overview tab.
/// Receives already-resolved values via init — no awareness of reference mode.
public struct ProjectHealthCard: View {

    private let health: ProjectExecutionModel.ProjectHealth
    private let progress: Double
    private let detail: String

    public init(
        health: ProjectExecutionModel.ProjectHealth,
        progress: Double,
        detail: String
    ) {
        self.health = health
        self.progress = progress
        self.detail = detail
    }

    public var body: some View {
        LiquidGlassCard("Project Health") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.m) {
                    LiquidCircularProgress(
                        value: progress,
                        title: "\(Int((progress * 100).rounded()))%",
                        size: healthGaugeSize,
                        color: projectHealthColor(health)
                    )
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        LiquidPill(
                            projectHealthLabel(health),
                            color: projectHealthColor(health),
                            filled: true
                        )
                        Text(detail)
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                healthAxis
            }
        }
    }

    /// Spec §Project Health: "small axis Off Track / At Risk / On Track" —
    /// the active state reads in its status color, the rest stay muted.
    private var healthAxis: some View {
        HStack(spacing: 0) {
            axisLabel("Off Track", active: health == .offTrack, color: DS.ColorToken.statusDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
            axisLabel("At Risk", active: health == .atRisk, color: DS.ColorToken.statusWarning)
                .frame(maxWidth: .infinity, alignment: .center)
            axisLabel("On Track", active: health == .onTrack, color: DS.ColorToken.statusSuccess)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health: \(projectHealthLabel(health))")
    }

    private func axisLabel(_ title: String, active: Bool, color: Color) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .foregroundStyle(active ? color : DS.ColorToken.textMuted)
    }
}

// MARK: - DeliveryRiskCard

/// Standalone "Delivery Risk" card for the Overview tab.
public struct DeliveryRiskCard: View {

    private let risks: [ProjectExecutionModel.ProjectRisk]
    private let tasks: [TaskItem]
    private let onOpenTask: (TaskItem) -> Void

    public init(
        risks: [ProjectExecutionModel.ProjectRisk],
        tasks: [TaskItem],
        onOpenTask: @escaping (TaskItem) -> Void
    ) {
        self.risks = risks
        self.tasks = tasks
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        LiquidGlassCard("Delivery Risk") {
            if risks.isEmpty {
                LiquidEmptyState(
                    systemImage: "checkmark.shield",
                    message: "No overdue tasks or looming deadlines."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(risks) { risk in
                        riskRow(risk)
                    }
                }
            }
        } trailing: {
            if !risks.isEmpty {
                LiquidPill("\(risks.count) at risk", color: DS.ColorToken.statusWarning)
            }
        }
    }

    private func riskRow(_ risk: ProjectExecutionModel.ProjectRisk) -> some View {
        Button {
            // Risk → real task-detail seam (the same `onOpenTask` chokepoint
            // the board and table route through).
            if let task = tasks.first(where: { $0.id == risk.taskID }) {
                onOpenTask(task)
            }
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(risk.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: DS.Space.s) {
                    LiquidPill(
                        risk.kind == .overdue ? "Overdue" : "Deadline",
                        color: risk.kind == .overdue
                            ? DS.ColorToken.statusDanger : DS.ColorToken.statusWarning
                    )
                    if let anchor = risk.kind == .overdue ? risk.dueAt : risk.deadlineAt {
                        Text(ProjectFormatters.monthDay.string(from: anchor))
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(DS.ColorToken.glassSoft)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(risk.title)")
    }
}

// MARK: - RecentActivityCard

/// Standalone "Recent Activity" card for the Overview tab.
public struct RecentActivityCard: View {

    private let activity: [ProjectExecutionModel.ActivityEntry]

    public init(activity: [ProjectExecutionModel.ActivityEntry]) {
        self.activity = activity
    }

    public var body: some View {
        LiquidGlassCard("Recent Activity") {
            if activity.isEmpty {
                LiquidEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    message: "No activity in this project yet."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(activity) { entry in
                        activityRow(entry)
                    }
                }
            }
        }
    }

    private func activityRow(_ entry: ProjectExecutionModel.ActivityEntry) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: activityIcon(entry.kind))
                // 12 pt feed glyph matches the inspector's other 12 pt accents.
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(activityColor(entry.kind))
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                Text("\(activityVerb(entry.kind)) · \(Self.relativeText(for: entry.timestamp))")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func activityIcon(_ kind: ProjectExecutionModel.ActivityKind) -> String {
        switch kind {
        case .taskCompleted: return "checkmark.circle"
        case .taskCreated: return "plus.circle"
        case .noteUpdated: return "doc.text"
        }
    }

    private func activityColor(_ kind: ProjectExecutionModel.ActivityKind) -> Color {
        switch kind {
        case .taskCompleted: return DS.ColorToken.accentGreen
        case .taskCreated: return DS.ColorToken.accentBlue
        case .noteUpdated: return DS.ColorToken.accentCyan
        }
    }

    private func activityVerb(_ kind: ProjectExecutionModel.ActivityKind) -> String {
        switch kind {
        case .taskCompleted: return "Completed"
        case .taskCreated: return "Created"
        case .noteUpdated: return "Note updated"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// A just-created entity's timestamp can land microseconds ahead of the
    /// render's `.now`, which the formatter renders as the nonsensical
    /// "in 0 sec" — clamp to now so fresh activity reads "now".
    private static func relativeText(for timestamp: Date) -> String {
        relativeFormatter.localizedString(for: min(timestamp, .now), relativeTo: .now)
    }
}

// MARK: - AINextStepsCard

/// Standalone "AI Next Steps" card for the Overview tab.
/// Intentional static placeholder — three deterministic guidance rows.
public struct AINextStepsCard: View {

    public init() {}

    public var body: some View {
        LiquidGlassCard("AI Next Steps") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                nextStepRow(
                    "Focus on the highest-risk delivery item",
                    color: DS.ColorToken.accentPrimary
                )
                nextStepRow(
                    "Review 2 unassigned high-priority tasks",
                    color: DS.ColorToken.statusWarning
                )
                nextStepRow(
                    "Prepare the next sprint plan",
                    color: DS.ColorToken.accentGreen
                )
            }
        }
    }

    private func nextStepRow(_ title: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
                .padding(.top, 2)
            Text(title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
