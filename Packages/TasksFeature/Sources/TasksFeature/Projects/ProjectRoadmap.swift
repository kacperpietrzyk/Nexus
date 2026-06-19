import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Roadmap lane geometry. These are fixed UI proportions rather than shared
/// design tokens, matching the local `MilestoneStrip` constants pattern.
private enum RoadmapMetrics {
    static let labelColumnWidth: CGFloat = 168
    static let headerHeight: CGFloat = 26
    static let rowHeight: CGFloat = 36
    static let barHeight: CGFloat = 20
    static let cycleLaneHeight: CGFloat = 30
    static let cycleBarHeight: CGFloat = 18
    static let markerSize: CGFloat = 8
    static let openEndedFadeWidth: CGFloat = 40
}

@MainActor
private enum RoadmapTickFormatter {
    static func label(for date: Date, zoom: RoadmapModel.Zoom, calendar: Calendar) -> String {
        formatter(for: zoom, calendar: calendar).string(from: date)
    }

    static func accessibilityDateLabel(for date: Date, calendar: Calendar) -> String {
        accessibilityDateFormatter(calendar: calendar).string(from: date)
    }

    private static func formatter(for zoom: RoadmapModel.Zoom, calendar: Calendar) -> DateFormatter {
        let formatter = baseFormatter(calendar: calendar)
        switch zoom {
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM yyyy"
        case .quarter:
            formatter.dateFormat = "QQQ yyyy"
        }
        return formatter
    }

    private static func accessibilityDateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = baseFormatter(calendar: calendar)
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    private static func baseFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}

struct ProjectRoadmap: View {
    let bars: [RoadmapModel.ProjectBar]
    let cycles: [RoadmapModel.CycleBar]
    let now: Date
    let calendar: Calendar
    let onSelectProject: (UUID) -> Void

    @State private var zoom: RoadmapModel.Zoom = .month

    var body: some View {
        LiquidGlassCard("Roadmap") {
            if bars.isEmpty {
                LiquidEmptyState(
                    systemImage: "calendar.day.timeline.left",
                    message: "No projects to map yet — roadmap dates derive from each project's tasks."
                )
            } else {
                timeline
            }
        } trailing: {
            LiquidSegmentedControl(
                options: RoadmapModel.Zoom.allCases.map { .init($0, label: $0.label) },
                selection: $zoom
            )
        }
    }

    private var totalHeight: CGFloat {
        RoadmapMetrics.headerHeight
            + (cycles.isEmpty ? 0 : RoadmapMetrics.cycleLaneHeight)
            + CGFloat(bars.count) * RoadmapMetrics.rowHeight
    }

    private var timeline: some View {
        let window = RoadmapModel.window(bars: bars, cycles: cycles, now: now, calendar: calendar)
        return HStack(alignment: .top, spacing: 0) {
            labelColumn
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(width: 1, height: totalHeight)
                .accessibilityHidden(true)
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    tickLayer(window)
                    laneRows(window)
                    todayLine(window)
                }
                .frame(
                    width: RoadmapModel.contentWidth(window: window, zoom: zoom, calendar: calendar),
                    height: totalHeight
                )
            }
        }
    }

    private var labelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 1, height: RoadmapMetrics.headerHeight)
            if !cycles.isEmpty {
                Text("Cycles")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .frame(height: RoadmapMetrics.cycleLaneHeight)
            }
            ForEach(bars) { bar in
                HStack(spacing: DS.Space.s) {
                    Image(systemName: nexusProjectGlyph(token: bar.glyphToken, id: bar.projectID))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    Text(bar.name)
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)
                }
                .frame(height: RoadmapMetrics.rowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }
        }
        .frame(width: RoadmapMetrics.labelColumnWidth)
        .padding(.trailing, DS.Space.s)
    }

    private func tickLayer(_ window: DateInterval) -> some View {
        ForEach(RoadmapModel.ticks(in: window, zoom: zoom, calendar: calendar), id: \.self) { tick in
            let x = RoadmapModel.xOffset(for: tick, in: window, zoom: zoom, calendar: calendar)
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(width: 1, height: totalHeight)
                .offset(x: x)
                .accessibilityHidden(true)
            Text(RoadmapTickFormatter.label(for: tick, zoom: zoom, calendar: calendar))
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
                .fixedSize()
                .offset(x: x + DS.Space.xs, y: 4)
                .accessibilityHidden(true)
        }
    }

    private func laneRows(_ window: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 1, height: RoadmapMetrics.headerHeight)
            if !cycles.isEmpty {
                cycleLane(window)
            }
            ForEach(bars) { bar in
                ZStack(alignment: .topLeading) {
                    barView(bar, window: window)
                        .offset(y: (RoadmapMetrics.rowHeight - RoadmapMetrics.barHeight) / 2)
                }
                .frame(height: RoadmapMetrics.rowHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func cycleLane(_ window: DateInterval) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(cycles) { cycle in
                let x = RoadmapModel.xOffset(for: cycle.startAt, in: window, zoom: zoom, calendar: calendar)
                let width = RoadmapModel.barWidth(from: cycle.startAt, to: cycle.endAt, zoom: zoom, calendar: calendar)
                cycleBar(cycle, width: width)
                    .offset(x: x, y: (RoadmapMetrics.cycleLaneHeight - RoadmapMetrics.cycleBarHeight) / 2)
            }
        }
        .frame(height: RoadmapMetrics.cycleLaneHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func cycleBar(_ cycle: RoadmapModel.CycleBar, width: CGFloat) -> some View {
        let color = Self.cycleColor(cycle.status)
        let textColor = cycle.status == .active ? DS.ColorToken.textPrimary : DS.ColorToken.textTertiary
        let fillOpacity = cycle.status == .active ? 0.28 : 0.14
        return Text(cycle.name)
            .font(DS.FontToken.caption)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(width: width, height: RoadmapMetrics.cycleBarHeight, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(color.opacity(fillOpacity))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            }
            .accessibilityLabel(cycleAccessibilityLabel(cycle, calendar: calendar))
    }

    private func cycleAccessibilityLabel(_ cycle: RoadmapModel.CycleBar, calendar: Calendar) -> String {
        let start = RoadmapTickFormatter.accessibilityDateLabel(for: cycle.startAt, calendar: calendar)
        let end = RoadmapTickFormatter.accessibilityDateLabel(for: cycle.endAt, calendar: calendar)
        return "\(cycle.name), \(cycleStatusLabel(cycle.status)) cycle, starts \(start), ends \(end)"
    }

    @ViewBuilder
    private func barView(_ bar: RoadmapModel.ProjectBar, window: DateInterval) -> some View {
        if !bar.scheduled {
            Button {
                onSelectProject(bar.projectID)
            } label: {
                Text("No schedule yet — add a key date")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .frame(height: RoadmapMetrics.barHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: RoadmapModel.xOffset(for: now, in: window, zoom: zoom, calendar: calendar))
        } else {
            scheduledBarView(bar, window: window)
        }
    }

    private func scheduledBarView(_ bar: RoadmapModel.ProjectBar, window: DateInterval) -> some View {
        let color = Self.healthColor(bar.health)
        let barX = RoadmapModel.xOffset(for: bar.start, in: window, zoom: zoom, calendar: calendar)
        let width = RoadmapModel.barWidth(from: bar.start, to: bar.end ?? window.end, zoom: zoom, calendar: calendar)
        let hasMarkers = !bar.milestones.isEmpty || !bar.keyDates.isEmpty
        let displayWidth = hasMarkers ? max(width, RoadmapMetrics.markerSize) : width
        let shape = RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
        return Button {
            onSelectProject(bar.projectID)
        } label: {
            ZStack(alignment: .leading) {
                shape.fill(color.opacity(0.16))
                shape
                    .fill(color.opacity(0.30))
                    .frame(width: max(0, displayWidth * CGFloat(bar.progress)))
                shape.strokeBorder(color.opacity(0.45), lineWidth: 1)
                markerLayer(bar, window: window, barX: barX, barWidth: displayWidth)
            }
            .frame(width: displayWidth, height: RoadmapMetrics.barHeight)
            .mask { openEndedMask(width: displayWidth, openEnded: bar.end == nil) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: barX)
        .accessibilityLabel(projectAccessibilityLabel(bar))
        .accessibilityHint("Opens the project")
    }

    private func markerLayer(
        _ bar: RoadmapModel.ProjectBar,
        window: DateInterval,
        barX: CGFloat,
        barWidth: CGFloat
    ) -> some View {
        let effectiveBarWidth = max(barWidth, RoadmapMetrics.markerSize)
        let halfMilestone = RoadmapMetrics.markerSize / 2
        // Key-date tick is a thin vertical capsule (width 2); half-width = 1.
        let keyDateTickWidth: CGFloat = 2
        let halfKeyDate: CGFloat = keyDateTickWidth / 2
        return Group {
            ForEach(bar.milestones) { marker in
                let markerX = RoadmapModel.xOffset(for: marker.date, in: window, zoom: zoom, calendar: calendar) - barX
                let clampedX = min(max(markerX, halfMilestone), effectiveBarWidth - halfMilestone)
                // A milestone dated before the project start (markerX < 0) or past
                // its end (> bar extent) gets clamped to the bar edge; dim it so a
                // clamped marker isn't mistaken for a real on-edge one. The threshold
                // is the bar's true date extent, not the half-marker render inset —
                // an on-start milestone resolves to markerX == 0 and must stay bright.
                let isOutOfRange = markerX < 0 || markerX > effectiveBarWidth
                Rectangle()
                    .fill(Self.markerColor(marker.state))
                    .frame(width: RoadmapMetrics.markerSize, height: RoadmapMetrics.markerSize)
                    .rotationEffect(.degrees(45))
                    .opacity(isOutOfRange ? 0.4 : 1)
                    .offset(x: clampedX - halfMilestone)
                    .accessibilityHidden(true)
            }
            ForEach(bar.keyDates) { keyDate in
                let markerX = RoadmapModel.xOffset(for: keyDate.date, in: window, zoom: zoom, calendar: calendar) - barX
                let clampedX = min(max(markerX, halfKeyDate), effectiveBarWidth - halfKeyDate)
                let isOutOfRange = markerX < 0 || markerX > effectiveBarWidth
                Capsule()
                    .fill(keyDate.isContractual ? DS.ColorToken.statusDanger : DS.ColorToken.accentPrimary)
                    .frame(width: keyDateTickWidth, height: RoadmapMetrics.barHeight)
                    .opacity(isOutOfRange ? 0.4 : 1)
                    .offset(x: clampedX - halfKeyDate)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func openEndedMask(width: CGFloat, openEnded: Bool) -> some View {
        if openEnded {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, 1 - RoadmapMetrics.openEndedFadeWidth / max(width, 1))),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }

    private func todayLine(_ window: DateInterval) -> some View {
        Rectangle()
            .fill(DS.ColorToken.accentPrimary)
            .frame(width: 1, height: totalHeight)
            .offset(x: RoadmapModel.xOffset(for: now, in: window, zoom: zoom, calendar: calendar))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static func healthColor(_ health: ProjectExecutionModel.ProjectHealth) -> Color {
        switch health {
        case .onTrack: return DS.ColorToken.statusSuccess
        case .atRisk: return DS.ColorToken.statusWarning
        case .offTrack: return DS.ColorToken.statusDanger
        }
    }

    private static func markerColor(_ state: ProjectExecutionModel.MilestoneState) -> Color {
        switch state {
        case .completed: return DS.ColorToken.accentGreen
        case .inProgress: return DS.ColorToken.accentPrimary
        case .upcoming: return DS.ColorToken.strokeStrong
        }
    }

    private static func cycleColor(_ status: CycleStatus) -> Color {
        switch status {
        case .upcoming: return DS.ColorToken.statusNeutral
        case .active: return DS.ColorToken.accentPrimary
        case .completed: return DS.ColorToken.accentGreen
        }
    }

    private func projectAccessibilityLabel(_ bar: RoadmapModel.ProjectBar) -> String {
        let percent = Int((bar.progress * 100).rounded())
        let start = RoadmapTickFormatter.accessibilityDateLabel(for: bar.start, calendar: calendar)
        let end = bar.end.map { "ends \(RoadmapTickFormatter.accessibilityDateLabel(for: $0, calendar: calendar))" } ?? "open-ended"
        return [
            bar.name,
            RoadmapModel.healthLabel(bar.health),
            "\(percent) percent complete",
            "starts \(start)",
            end,
            milestoneAccessibilitySummary(bar.milestones),
        ].joined(separator: ", ")
    }

    private func milestoneAccessibilitySummary(_ milestones: [RoadmapModel.MilestoneMarker]) -> String {
        guard !milestones.isEmpty else { return "no dated milestones" }

        let count = milestones.count
        let countLabel = count == 1 ? "1 dated milestone" : "\(count) dated milestones"
        let details = milestones.prefix(3).map { marker in
            let date = RoadmapTickFormatter.accessibilityDateLabel(for: marker.date, calendar: calendar)
            return "\(marker.title) \(milestoneStateLabel(marker.state)) on \(date)"
        }
        .joined(separator: "; ")

        if count > 3 {
            return "\(countLabel): \(details); and \(count - 3) more"
        }
        return "\(countLabel): \(details)"
    }

    private func milestoneStateLabel(_ state: ProjectExecutionModel.MilestoneState) -> String {
        switch state {
        case .completed: return "completed"
        case .inProgress: return "in progress"
        case .upcoming: return "upcoming"
        }
    }

    private func cycleStatusLabel(_ status: CycleStatus) -> String {
        switch status {
        case .upcoming: return "upcoming"
        case .active: return "active"
        case .completed: return "completed"
        }
    }
}
