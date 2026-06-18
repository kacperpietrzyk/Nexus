import NexusCore
import NexusUI
import SwiftUI

/// `Top Priorities` card (spec §Main top row 2): a ranked "do-now" shortlist of
/// ≤5 tasks (pinned → overdue → priority high→low → due soonest → stable index),
/// with `LiquidTaskRow`s showing a real completion checkbox, project tag pill, and
/// an overdue indicator only when the task is actually overdue.
struct TopPrioritiesCard: View {

    let groups: [LiquidPriorityGroup]
    /// False until the model's first store load completes. While false the card
    /// renders a layout-stable empty body (no placeholder rows) so the genuine
    /// empty state isn't flashed during the ~100ms cold-start before real rows
    /// arrive — preventing the "two looks" dimension shift.
    let isLoaded: Bool
    let now: Date
    let projectName: (UUID) -> String?
    let onToggle: (TaskItem) -> Void
    let onOpen: (TaskItem) -> Void
    let onAddTask: () -> Void
    let onViewAll: () -> Void

    var body: some View {
        TodayGlassCard("Top Priorities") {
            if !isLoaded {
                // Pre-first-load: keep the card frame present but show nothing —
                // no divergent placeholder, no dimension flash. Same fill frame
                // as the real / empty bodies so the card height never collapses.
                VStack(alignment: .leading, spacing: DS.Space.m) {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if groups.isEmpty {
                emptySummary
            } else {
                let startOfToday = Calendar.current.startOfDay(for: now)
                let ranked = LiquidTodayModel.rankedTodayPriorities(
                    groups.flatMap(\.tasks),
                    now: startOfToday
                )
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    ForEach(ranked, id: \.id) { task in
                        row(task)
                    }
                    Spacer(minLength: 0)
                    LiquidCardFooterLink("View all tasks", action: onViewAll)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var emptySummary: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                emptyRow(
                    "High Priority",
                    color: DS.ColorToken.accentRed,
                    message: "No urgent tasks due today"
                )
                emptyRow(
                    "Medium Priority",
                    color: DS.ColorToken.accentAmber,
                    message: "No scheduled follow-ups"
                )
                emptyRow(
                    "Low Priority",
                    color: DS.ColorToken.accentBlue,
                    message: "Backlog is quiet"
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.Space.m) {
                LiquidCardFooterLink("View all tasks", action: onViewAll)
                Spacer()
                LiquidPrimaryButton("Add task", systemImage: "plus", action: onAddTask)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func emptyRow(_ title: String, color: Color, message: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Circle()
                .stroke(color.opacity(0.46), lineWidth: 1.25)
                .background {
                    Circle()
                        .fill(color.opacity(0.08))
                }
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.FontToken.metadata.weight(.semibold))
                    .foregroundStyle(color)
                Text(message)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 46)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(Color.white.opacity(0.007))
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.026),
                            .clear,
                            Color.black.opacity(0.016),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                }
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: 3)
                        .padding(.vertical, DS.Space.s)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(Color.white.opacity(0.042), lineWidth: 1)
        }
        .shadow(color: color.opacity(0.028), radius: 7, x: 0, y: 0)
    }

    private func row(_ task: TaskItem) -> some View {
        LiquidTaskRow(
            task.title,
            isDone: task.status == .done,
            metadata: Self.dueLabel(for: task, now: now),
            onToggle: { onToggle(task) },
            accessory: {
                if let projectID = task.projectID, let name = projectName(projectID) {
                    LiquidPill(name, color: DS.ColorToken.accentBlue)
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen(task) }
    }

    /// Human-readable label for a priority level (also used by Kanban and other views).
    static func label(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "High Priority"
        case .medium: return "Medium Priority"
        case .low: return "Low Priority"
        case .none: return "No Priority"
        }
    }

    /// Accent color for a priority level (also used by Kanban and other views).
    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .high: return DS.ColorToken.accentRed
        case .medium: return DS.ColorToken.accentAmber
        case .low: return DS.ColorToken.accentBlue
        case .none: return DS.ColorToken.textTertiary
        }
    }

    /// Overdue indicator: shown ONLY when the task is overdue. Today, future,
    /// and undated tasks return nil (no label in the ranked shortlist).
    static func dueLabel(for task: TaskItem, now: Date) -> String? {
        guard let due = task.dueAt else { return nil }
        let startOfToday = Calendar.current.startOfDay(for: now)
        guard due < startOfToday else { return nil }
        return "Overdue · \(dueDayFormatter.string(from: due))"
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dueDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// Shared "View all … →" accent footer link used by the Today cards
/// (reference `01_today_dashboard.png` bottom-of-card links).
struct LiquidCardFooterLink: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xxs) {
                Text(title)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(DS.FontToken.metadata.weight(.medium))
            .foregroundStyle(DS.ColorToken.accentPrimaryHover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
