import Charts
import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct ProductivityDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var dailyCounts: [ProductivityStatsService.DailyCount] = []
    @State private var streak = 0
    @State private var perProject: [ProductivityStatsService.PerProject] = []

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 14) {
                    streakCard
                    totalCard
                }

                completionsChartCard
                projectBreakdownCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("PRODUCTIVITY")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            Text("Statistics")
                .font(NexusType.h1)
                .foregroundStyle(NexusColor.Text.primary)

            Text("Task-completion rhythm over the last 30 days.")
                .nexusType(.body)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 220), spacing: 14)
        ]
    }

    private var streakCard: some View {
        NexusCard(.elev2, padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .frame(width: 38, height: 38)
                    .background(NexusColor.Background.controlHover, in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Current streak")
                        .nexusType(.eyebrow)
                        .foregroundStyle(NexusColor.Text.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak)")
                            .nexusType(.h2)
                            .foregroundStyle(NexusColor.Text.primary)
                        Text(streakUnitLabel)
                            .nexusType(.bodySmall)
                            .foregroundStyle(NexusColor.Text.secondary)
                    }
                }

                Spacer(minLength: 8)

                MiniBarStrip(entries: Array(dailyCounts.suffix(7)))
            }
        }
    }

    private var totalCard: some View {
        NexusCard(.elev1, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last 30 days")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Text("\(completedTotal)")
                    .nexusType(.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                Text(completedTaskLabel)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }

    private var completionsChartCard: some View {
        NexusCard(.elev1, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Completed", detail: "Last 30 days")

                if completedTotal == 0 {
                    EmptyStatsState(
                        systemImage: "chart.bar",
                        title: "No completions yet",
                        subtitle: "The chart will appear after you complete your first tasks."
                    )
                    .frame(height: 172)
                } else {
                    Chart(dailyCounts) { entry in
                        BarMark(
                            x: .value("Day", entry.day, unit: .day),
                            y: .value("Completed", entry.count),
                            width: .fixed(24)
                        )
                        .foregroundStyle(NexusColor.Text.secondary)
                        .opacity(entry.count >= 1 ? 0.54 : 0.0)
                        .cornerRadius(3)
                    }
                    .chartYScale(domain: 0...chartYUpperBound)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(NexusColor.Line.hairline)
                            AxisTick()
                                .foregroundStyle(NexusColor.Line.regular)
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(NexusColor.Text.muted)
                                .font(NexusType.caption)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(NexusColor.Line.hairline)
                            AxisValueLabel()
                                .foregroundStyle(NexusColor.Text.muted)
                                .font(NexusType.caption)
                        }
                    }
                    .frame(height: 172)
                }
            }
        }
    }

    private var projectBreakdownCard: some View {
        NexusCard(.elev1, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "By project", detail: "Completed in the last 30 days")

                if perProject.isEmpty {
                    EmptyStatsState(
                        systemImage: "folder",
                        title: "No project completions",
                        subtitle: "Tasks assigned to projects will appear here."
                    )
                    .frame(height: 120)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(perProject) { entry in
                            ProjectBreakdownRow(entry: entry, maxCount: maxProjectCount)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .nexusType(.h3)
                .foregroundStyle(NexusColor.Text.primary)
            Spacer(minLength: 12)
            Text(detail)
                .nexusType(.meta)
                .foregroundStyle(NexusColor.Text.muted)
        }
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
                    .fill(entry.count >= 1 ? NexusColor.Text.primary : NexusColor.Background.control)
                    .frame(width: 5, height: 12 + CGFloat(index * 2))
                    .opacity(entry.count >= 1 ? 1 : 0.7)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ProjectBreakdownRow: View {
    let entry: ProductivityStatsService.PerProject
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.projectName)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(entry.completedCount)")
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NexusColor.Background.control)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NexusColor.Text.primary)
                        .frame(width: proxy.size.width * CGFloat(entry.completedCount) / CGFloat(maxCount))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.projectName), \(entry.completedCount) completed")
    }
}

private struct EmptyStatsState: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NexusColor.Text.muted)
            Text(title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
            Text(subtitle)
                .nexusType(.caption)
                .foregroundStyle(NexusColor.Text.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NexusColor.Background.control.opacity(0.24), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        }
    }
}
