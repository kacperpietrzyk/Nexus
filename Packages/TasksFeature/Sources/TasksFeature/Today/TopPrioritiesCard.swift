import NexusCore
import NexusUI
import SwiftUI

/// Rows shown per priority section before deferring to the Tasks list — keeps
/// the card a summary, not a second task manager.
private let prioritySectionRowCap = 5

/// `Top Priorities` card (spec §Main top row 2): today's + overdue tasks
/// grouped High/Medium/Low (section labels red/amber/blue per
/// `docs/05_MODULE_TODAY.md` §Top Priorities), `LiquidTaskRow`s with a real
/// completion checkbox, project tag pill, and trailing due metadata.
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
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    ForEach(groups) { group in
                        section(group)
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

    private func section(_ group: LiquidPriorityGroup) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.xs) {
                Text(Self.label(for: group.priority))
                    // Section label: 11 pt semibold in the priority color
                    // (spec §Top Priorities High=red / Medium=amber / Low=blue);
                    // metadata token at semibold — no dedicated token exists.
                    .font(DS.FontToken.metadata.weight(.semibold))
                    .foregroundStyle(Self.color(for: group.priority))
                Text("\(group.tasks.count)")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .monospacedDigit()
            }

            ForEach(group.tasks.prefix(prioritySectionRowCap), id: \.id) { task in
                row(task)
            }
            if group.tasks.count > prioritySectionRowCap {
                Text("+\(group.tasks.count - prioritySectionRowCap) more")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .padding(.horizontal, DS.Space.s)
            }
        }
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

    static func label(for priority: TaskPriority) -> String {
        switch priority {
        case .high: return "High Priority"
        case .medium: return "Medium Priority"
        case .low: return "Low Priority"
        case .none: return "No Priority"
        }
    }

    static func color(for priority: TaskPriority) -> Color {
        switch priority {
        case .high: return DS.ColorToken.accentRed
        case .medium: return DS.ColorToken.accentAmber
        case .low: return DS.ColorToken.accentBlue
        case .none: return DS.ColorToken.textTertiary
        }
    }

    /// Trailing due metadata (spec: tertiary, right aligned): "Due today",
    /// "Overdue · Jun 3", or "Due Jun 14".
    static func dueLabel(for task: TaskItem, now: Date) -> String? {
        guard let due = task.dueAt else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(due, inSameDayAs: now) { return "Due today" }
        let dayText = dueDayFormatter.string(from: due)
        if due < calendar.startOfDay(for: now) { return "Overdue · \(dayText)" }
        return "Due \(dayText)"
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
