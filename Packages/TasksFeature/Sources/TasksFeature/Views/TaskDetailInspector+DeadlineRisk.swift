import NexusCore
import NexusUI
import SwiftUI

// MARK: - Deadline-risk badge (spec §19.1 D1, inspector half)

// The forward-looking deadline-risk signal for the selected task, rendered as an
// inline row inside `deadlineCard`. Computed locally from the store via the same
// NexusCore `DeadlineRiskProjector` the Today banner uses — the inspector lives
// in TasksFeature and already holds a `modelContext`, so no Today/global state is
// threaded in. Pure signal, never an action (spec §19.1). Calendar obstacles are
// not fetched here (synchronous render path) → `events: []`, i.e. raw
// working-window feasibility; the Today banner, which fetches the horizon, is the
// authoritative view. Achromatic Nexus* tokens, mirroring the banner.

extension TaskDetailInspector {
    /// The selected task's risk entry, or nil when it is not open, has no future
    /// deadline, or the projection finds no pressure for it.
    var selectedTaskRisk: DeadlineRisk? {
        guard task.deletedAt == nil, task.status == .open else { return nil }
        let now = Date.now
        guard let deadline = task.deadlineAt, deadline > now else { return nil }
        // Horizon must reach this task's deadline so it gets a risk entry.
        let horizon = max(deadline.timeIntervalSince(now) + 86_400, 86_400)
        let prefs = UserDefaultsCalendarPreferencesStore().load()
        let risks = DeadlineRiskProjector.project(
            context: modelContext,
            events: [],
            prefs: prefs,
            horizon: horizon,
            now: now,
            calendar: .current
        )
        return risks.first { $0.taskID == task.id }
    }

    /// Inline risk row for `deadlineCard`; self-omits when the task is `onTrack`.
    @ViewBuilder
    func deadlineRiskRow() -> some View {
        if let risk = selectedTaskRisk, risk.severity != .onTrack {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Text(Self.deadlineRiskRowMessage(risk))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Deadline risk: \(Self.deadlineRiskRowMessage(risk))")
        }
    }

    /// "At risk · start by HH:mm" / "Tight · start by HH:mm", or a tier fallback
    /// when no start time is known. Never an empty string.
    static func deadlineRiskRowMessage(_ risk: DeadlineRisk) -> String {
        let tier = risk.severity == .atRisk ? "At risk" : "Tight"
        if let startBy = risk.suggestedStartBy {
            return "\(tier) · start by \(deadlineRiskTimeFormatter.string(from: startBy))"
        }
        return risk.severity == .atRisk
            ? "At risk · projected to miss the deadline"
            : "Tight · little slack before the deadline"
    }

    private static let deadlineRiskTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
