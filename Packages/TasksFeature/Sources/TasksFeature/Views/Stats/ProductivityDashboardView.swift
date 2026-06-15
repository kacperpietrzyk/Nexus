import Charts
import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Stat-numeral display size — no DS.FontToken carries a numeric-display
/// weight; 26 pt sits inside the reference boards' 22–28 pt stat band
/// (visual calibration, same precedent as the glass-highlight 0.55).
private let statNumeralFont = Font.system(size: 26, weight: .semibold)

public struct ProductivityDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var dailyCounts: [ProductivityStatsService.DailyCount] = []
    @State private var streak = 0
    @State private var perProject: [ProductivityStatsService.PerProject] = []
    @State private var goalProgress: ProductivityStatsService.GoalProgress?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                header

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: DS.Space.m) {
                    streakCard
                    totalCard
                }

                if let goalProgress, goalProgress.dailyTarget > 0 || goalProgress.weeklyTarget > 0 {
                    goalsCard(goalProgress)
                }

                completionsChartCard
                projectBreakdownCard
            }
            .padding(.horizontal, DS.Space.xxl)
            .padding(.vertical, DS.Space.xl)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .task { await reload() }
        .reloadOnStoreChange { _Concurrency.Task { await reload() } }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            _Concurrency.Task { await reload() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            eyebrow("Productivity")

            Text("Statistics")
                .font(DS.FontToken.displayLarge)
                .foregroundStyle(DS.ColorToken.textPrimary)

            Text("Task-completion rhythm over the last 30 days.")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 220), spacing: DS.Space.m)
        ]
    }

    private var streakCard: some View {
        LiquidGlassCard {
            HStack(alignment: .center, spacing: DS.Space.m) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(
                        DS.ColorToken.glassSelected,
                        in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    eyebrow("Current streak")
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                        Text("\(streak)")
                            .font(statNumeralFont)
                            .monospacedDigit()
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Text(streakUnitLabel)
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }
                }

                Spacer(minLength: DS.Space.s)

                MiniBarStrip(entries: Array(dailyCounts.suffix(7)))
            }
        }
    }

    private var totalCard: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                eyebrow("Last 30 days")
                Text("\(completedTotal)")
                    .font(statNumeralFont)
                    .monospacedDigit()
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text(completedTaskLabel)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
    }

    private var completionsChartCard: some View {
        LiquidGlassCard("Completed") {
            if completedTotal == 0 {
                LiquidEmptyState(
                    systemImage: "chart.bar",
                    message: "The chart will appear after you complete your first tasks."
                )
                .frame(height: 172)
                .frame(maxWidth: .infinity)
            } else {
                Chart(dailyCounts) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Completed", entry.count),
                        width: .fixed(24)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DS.ColorToken.accentPrimaryHover, DS.ColorToken.accentPrimary],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(entry.count >= 1 ? 0.92 : 0.0)
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...chartYUpperBound)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(DS.ColorToken.strokeHairline)
                        AxisTick()
                            .foregroundStyle(DS.ColorToken.strokeDefault)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .font(DS.FontToken.caption)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(DS.ColorToken.strokeHairline)
                        AxisValueLabel()
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .font(DS.FontToken.caption.monospacedDigit())
                    }
                }
                .frame(height: 172)
            }
        } trailing: {
            Text("Last 30 days")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }

    private var projectBreakdownCard: some View {
        LiquidGlassCard("By project") {
            if perProject.isEmpty {
                LiquidEmptyState(
                    systemImage: "folder",
                    message: "Tasks assigned to projects will appear here."
                )
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    ForEach(perProject) { entry in
                        ProjectBreakdownRow(entry: entry, maxCount: maxProjectCount)
                    }
                }
            }
        } trailing: {
            Text("Completed in the last 30 days")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }

    private func goalsCard(_ progress: ProductivityStatsService.GoalProgress) -> some View {
        LiquidGlassCard("Goals") {
            HStack(alignment: .center, spacing: DS.Space.xl) {
                if progress.dailyTarget > 0 {
                    goalRing(
                        fraction: progress.dailyFraction,
                        completed: progress.dailyCompleted,
                        target: progress.dailyTarget,
                        caption: "Today"
                    )
                }
                if progress.weeklyTarget > 0 {
                    goalRing(
                        fraction: progress.weeklyFraction,
                        completed: progress.weeklyCompleted,
                        target: progress.weeklyTarget,
                        caption: "This week"
                    )
                }
                if let copy = Self.goalStatusCopy(for: progress) {
                    Text(copy)
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
            }
        } trailing: {
            Text("Targets in Settings")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }

    private func goalRing(fraction: Double, completed: Int, target: Int, caption: String) -> some View {
        VStack(spacing: DS.Space.xs) {
            LiquidCircularProgress(value: fraction, title: "\(completed)/\(target)")
            eyebrow(caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(completed) of \(target) tasks completed")
    }

    /// Status line under the goal rings. Priority: streak protection > goal
    /// reached > remaining count. A disabled daily target (0 = off) yields no
    /// copy at all — streak protection belongs to the daily goal and must not
    /// cross-fire onto a weekly-only card (defense in depth: the service
    /// already withholds `streakAtRisk` when the daily target is disabled).
    /// Internal (not private) so tests pin the rules.
    static func goalStatusCopy(for progress: ProductivityStatsService.GoalProgress) -> String? {
        guard progress.dailyTarget > 0 else { return nil }
        if let streak = progress.streakAtRisk {
            return "Complete a task today to keep your \(streak)-day streak."
        }
        if progress.dailyCompleted >= progress.dailyTarget {
            return "Daily goal reached — nice work."
        }
        let remaining = progress.dailyTarget - progress.dailyCompleted
        return remaining == 1 ? "1 task to go today." : "\(remaining) tasks to go today."
    }

    /// Tracked-caption eyebrow shared by the header and stat tiles — same
    /// uppercase + kerning idiom as `LiquidSidebarSectionHeader`.
    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .textCase(.uppercase)
            .kerning(0.6)
    }

    private var completedTotal: Int {
        dailyCounts.reduce(0) { $0 + $1.count }
    }

    private var chartYUpperBound: Int {
        max(dailyCounts.map(\.count).max() ?? 0, 3)
    }

    private var maxProjectCount: Int {
        max(perProject.map(\.completedCount).max() ?? 1, 1)
    }

    private var streakUnitLabel: String {
        streak == 1 ? "day" : "days"
    }

    private var completedTaskLabel: String {
        completedTotal == 1 ? "task completed" : "tasks completed"
    }

    @MainActor
    private func reload() async {
        let service = ProductivityStatsService(context: modelContext)
        let now = Date.now
        dailyCounts = (try? service.completedPerDay(last: 30, now: now)) ?? []
        streak = (try? service.currentStreakDays(now: now)) ?? 0
        let goalsPreferences = UserDefaultsGoalsPreferencesStore().load()
        goalProgress = try? service.goalProgress(preferences: goalsPreferences, now: now)

        // Use the service's calendar so injected test calendars (and future
        // user-locale overrides) flow through to the per-project window.
        let calendar = service.calendar
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        perProject = (try? service.completedPerProject(since: since)) ?? []
    }
}

private struct MiniBarStrip: View {
    let entries: [ProductivityStatsService.DailyCount]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(entry.count >= 1 ? AnyShapeStyle(DS.ColorToken.accentPrimary) : AnyShapeStyle(DS.ColorToken.glassSelected))
                    .frame(width: 5, height: 12 + CGFloat(index * 2))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ProjectBreakdownRow: View {
    let entry: ProductivityStatsService.PerProject
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text(entry.projectName)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                Text("\(entry.completedCount)")
                    .font(DS.FontToken.metadata)
                    .monospacedDigit()
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }

            LiquidProgressLine(value: Double(entry.completedCount) / Double(maxCount))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.projectName), \(entry.completedCount) completed")
    }
}
