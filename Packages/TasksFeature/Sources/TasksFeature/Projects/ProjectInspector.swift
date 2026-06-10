import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/03_COMPONENTS.md` §CircularProgress: project health gauge 62–70 pt.
private let healthGaugeSize: CGFloat = 66

/// The Projects right inspector (spec §Right inspector): Project Health,
/// Delivery Risk, and Recent Activity as vertical glass cards over the shared
/// `LiquidProjectsModel`. Mounted by the app shell in the 304 pt slot only
/// while a project is selected.
///
/// The spec's "AI Next Steps" card is intentionally OMITTED: the only agent
/// seam in the app (`AgentBriefService`) is shaped around Today's task counts
/// — there is no project-scoped suggestion provider, and fabricating
/// "prioritized suggestions" without one would violate the real-data rule.
public struct ProjectInspector: View {

    private let model: LiquidProjectsModel
    private let onOpenTask: (TaskItem) -> Void

    public init(model: LiquidProjectsModel, onOpenTask: @escaping (TaskItem) -> Void) {
        self.model = model
        self.onOpenTask = onOpenTask
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            // 04_LAYOUT_SYSTEM.md: "Prawy panel ma własne karty ułożone w
            // pionie, spacing 12".
            VStack(spacing: DS.Space.m) {
                healthCard
                riskCard
                activityCard
            }
            .padding(DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Project Health

    private var healthCard: some View {
        LiquidGlassCard("Project Health") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.m) {
                    LiquidCircularProgress(
                        value: model.progress,
                        title: "\(Int((model.progress * 100).rounded()))%",
                        size: healthGaugeSize,
                        color: healthColor
                    )
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        LiquidPill(healthLabel, color: healthColor, filled: true)
                        Text(healthDetail)
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
            axisLabel("Off Track", active: model.health == .offTrack, color: DS.ColorToken.statusDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
            axisLabel("At Risk", active: model.health == .atRisk, color: DS.ColorToken.statusWarning)
                .frame(maxWidth: .infinity, alignment: .center)
            axisLabel("On Track", active: model.health == .onTrack, color: DS.ColorToken.statusSuccess)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health: \(healthLabel)")
    }

    private func axisLabel(_ title: String, active: Bool, color: Color) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .foregroundStyle(active ? color : DS.ColorToken.textMuted)
    }

    private var healthColor: Color {
        switch model.health {
        case .onTrack: return DS.ColorToken.statusSuccess
        case .atRisk: return DS.ColorToken.statusWarning
        case .offTrack: return DS.ColorToken.statusDanger
        }
    }

    private var healthLabel: String {
        switch model.health {
        case .onTrack: return "On Track"
        case .atRisk: return "At Risk"
        case .offTrack: return "Off Track"
        }
    }

    private var healthDetail: String {
        let open = model.tasks.count(where: { $0.status != .done })
        let done = model.tasks.count - open
        return "\(done) done · \(open) open"
    }

    // MARK: - Delivery Risk

    private var riskCard: some View {
        LiquidGlassCard("Delivery Risk") {
            if model.risks.isEmpty {
                LiquidEmptyState(
                    systemImage: "checkmark.shield",
                    message: "No overdue tasks or looming deadlines."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(model.risks) { risk in
                        riskRow(risk)
                    }
                }
            }
        } trailing: {
            if !model.risks.isEmpty {
                LiquidPill("\(model.risks.count) at risk", color: DS.ColorToken.statusWarning)
            }
        }
    }

    private func riskRow(_ risk: ProjectExecutionModel.ProjectRisk) -> some View {
        Button {
            // Risk → real task-detail seam (the same `onOpenTask` chokepoint
            // the board and table route through).
            if let task = model.tasks.first(where: { $0.id == risk.taskID }) {
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
                        color: risk.kind == .overdue ? DS.ColorToken.statusDanger : DS.ColorToken.statusWarning
                    )
                    if let anchor = risk.kind == .overdue ? risk.dueAt : risk.deadlineAt {
                        Text(Self.dateFormatter.string(from: anchor))
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

    // MARK: - Recent Activity

    private var activityCard: some View {
        LiquidGlassCard("Recent Activity") {
            if model.activity.isEmpty {
                LiquidEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    message: "No activity in this project yet."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(model.activity) { entry in
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

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

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
