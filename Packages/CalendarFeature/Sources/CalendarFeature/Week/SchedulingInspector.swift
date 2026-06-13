import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Pure week-scope derivations over `SchedulingIntelligence` (unit-tested):
/// workday windows, aggregate meeting load, today's focus gaps, and the
/// next-free-gap search Quick Reschedule uses.
enum WeekIntelligence {
    /// Standard 08:00–18:00 workday — mirrors `LiquidTodayModel`'s focus-gap
    /// window constants (no workday token exists in the DS).
    static let workdayStartHour = 8
    static let workdayEndHour = 18

    /// The 8 AM–6 PM window of `day`, or nil if calendar math fails.
    static func workdayWindow(for day: Date, calendar: Calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: day)
        guard
            let start = calendar.date(byAdding: .hour, value: workdayStartHour, to: dayStart),
            let end = calendar.date(byAdding: .hour, value: workdayEndHour, to: dayStart),
            start < end
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Aggregate meeting load over the visible week's workdays (weekend days
    /// skipped): unioned meeting seconds / total workday seconds. Mirror
    /// events of accepted blocks count as focus, not meetings.
    static func weekMeetingLoad(
        events: [CalendarEvent],
        days: [Date],
        calendar: Calendar,
        mirroredEventIDs: Set<String>
    ) -> Double {
        var workdaySeconds: TimeInterval = 0
        var meetingSeconds: TimeInterval = 0
        for day in days where !calendar.isDateInWeekend(day) {
            guard let window = workdayWindow(for: day, calendar: calendar) else { continue }
            let load = SchedulingIntelligence.meetingLoad(
                events: events,
                workday: window,
                isMeeting: { WeekEventClassifier.category(for: $0, mirroredEventIDs: mirroredEventIDs) == .meeting }
            )
            workdaySeconds += window.duration
            meetingSeconds += load * window.duration
        }
        guard workdaySeconds > 0 else { return 0 }
        return meetingSeconds / workdaySeconds
    }

    /// Free ≥1 h gaps left in TODAY's workday when today is one of `days`
    /// (clamped to `now` so past gaps never get suggested).
    static func todayFocusGaps(
        events: [CalendarEvent],
        days: [Date],
        calendar: Calendar,
        now: Date
    ) -> [DateInterval] {
        guard
            let today = days.first(where: { calendar.isDate($0, inSameDayAs: now) }),
            let window = workdayWindow(for: today, calendar: calendar)
        else { return [] }
        let start = max(window.start, now)
        guard start < window.end else { return [] }
        return SchedulingIntelligence.suggestedFocusBlocks(
            events: events,
            within: DateInterval(start: start, end: window.end),
            // Discrete 2 h suggestions per the reference board — an empty
            // workday must not read as one 10 h "focus block".
            maximumDuration: 2 * 3600
        )
    }

    /// First `duration`-long slot inside the week's workday windows starting
    /// at/after `after` — the Quick Reschedule target.
    static func nextFitGap(
        after: Date,
        duration: TimeInterval,
        events: [CalendarEvent],
        days: [Date],
        calendar: Calendar
    ) -> DateInterval? {
        guard duration > 0 else { return nil }
        for day in days where !calendar.isDateInWeekend(day) {
            guard
                let window = workdayWindow(for: day, calendar: calendar),
                window.end > after
            else { continue }
            let searchStart = max(window.start, after)
            guard searchStart < window.end else { continue }
            let gaps = SchedulingIntelligence.suggestedFocusBlocks(
                events: events,
                within: DateInterval(start: searchStart, end: window.end),
                minimumDuration: duration
            )
            if let gap = gaps.first {
                return DateInterval(start: gap.start, duration: duration)
            }
        }
        return nil
    }
}

/// The Calendar right inspector (304 pt slot, `docs/06_MODULE_CALENDAR.md`
/// §Right inspector): Scheduling Intelligence as vertical glass cards —
/// Meeting Load, Conflicts, Suggested Focus Blocks, Quick Reschedule, and
/// Time Insights — all derived from the SAME `CalendarViewModel` the main
/// column renders, via the `SchedulingIntelligence` seams.
public struct SchedulingInspector: View {

    private let viewModel: CalendarViewModel
    private let calendar: Calendar
    private let now: () -> Date

    @State private var editorTarget: WeekEditorTarget?
    @State private var availableCalendars: [CalendarInfo] = []

    /// Spec §Meeting Load mirrors the Today Focus Timer ring scale (62–70 pt).
    private static let ringSize: CGFloat = 66
    private static let maxFocusGapRows = 3

    public init(
        viewModel: CalendarViewModel,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.now = now
    }

    public var body: some View {
        // No ScrollView — the inspector is a fixed column that fits the window
        // height (matches the Today inspector). Empty cards collapse to a
        // single muted line via `inspectorEmptyLine`.
        VStack(spacing: DS.Space.m) {
            meetingLoadCard
            conflictsCard
            focusBlocksCard
            if !conflicts.isEmpty && (viewModel.hasCalendarAccess || LiquidReferenceMode.isEnabled) {
                quickRescheduleCard
            }
            timeInsightsCard
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            availableCalendars = await viewModel.availableCalendars()
            // Single source of truth: the unscheduled list lives on the shared
            // view-model (see `CalendarViewModel.unscheduledTasks`), so a
            // schedule action from either column updates both.
            viewModel.reloadUnscheduledTasks()
        }
        .weekEventEditorSheet(target: $editorTarget, viewModel: viewModel, calendars: availableCalendars)
    }

    // MARK: - Derived intelligence (shared seams)

    private var mirroredEventIDs: Set<String> {
        Set(viewModel.blocks.compactMap(\.externalEventID))
    }

    private var reference: LiquidWeekReferenceData.Snapshot? {
        LiquidReferenceMode.isEnabled
            ? LiquidWeekReferenceData.snapshot(days: viewModel.visibleDays, now: now(), calendar: calendar)
            : nil
    }

    private var intelligenceEvents: [CalendarEvent] {
        reference?.events ?? viewModel.events
    }

    private var intelligenceDays: [Date] {
        reference?.days ?? viewModel.visibleDays
    }

    private var unscheduledTasks: [WeekUnscheduledTask] {
        reference?.unscheduledTasks ?? viewModel.unscheduledTasks
    }

    private var conflicts: [SchedulingIntelligence.EventConflict] {
        SchedulingIntelligence.conflicts(in: intelligenceEvents)
    }

    private var meetingLoad: Double {
        WeekIntelligence.weekMeetingLoad(
            events: intelligenceEvents,
            days: intelligenceDays,
            calendar: calendar,
            mirroredEventIDs: mirroredEventIDs
        )
    }

    private var focusGaps: [DateInterval] {
        if let reference {
            return reference.focusGaps
        }
        return WeekIntelligence.todayFocusGaps(
            events: viewModel.events,
            days: viewModel.visibleDays,
            calendar: calendar,
            now: now()
        )
    }

    private var weekWindow: DateInterval {
        if let first = intelligenceDays.first, let last = intelligenceDays.last {
            let start = calendar.startOfDay(for: first)
            let lastStart = calendar.startOfDay(for: last)
            let end = calendar.date(byAdding: .day, value: 1, to: lastStart) ?? lastStart
            return DateInterval(start: start, end: end)
        }
        // `viewModel.window` is a named tuple `(start: Date, end: Date)`, not
        // a DateInterval — the conversion here is intentional, for the
        // interval-based SchedulingIntelligence API.
        let window = viewModel.window
        return DateInterval(start: window.start, end: window.end)
    }

    /// Compact empty affordance for inspector cards: one muted line, no hero
    /// glyph — keeps an empty card ~1 row tall so the column fits without scroll.
    private func inspectorEmptyLine(_ message: String) -> some View {
        Text(message)
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meeting Load

    private var meetingLoadCard: some View {
        LiquidGlassCard("Meeting Load") {
            HStack(spacing: DS.Space.m) {
                LiquidCircularProgress(
                    value: meetingLoad,
                    title: "\(Int((meetingLoad * 100).rounded()))%",
                    size: Self.ringSize,
                    color: DS.ColorToken.accentPurple
                )
                Text("of this week's workday hours are in meetings.")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Conflicts

    @ViewBuilder
    private var conflictsCard: some View {
        LiquidGlassCard("Conflicts") {
            if conflicts.isEmpty {
                inspectorEmptyLine("No overlapping events this week.")
            } else {
                VStack(spacing: DS.Space.s) {
                    ForEach(conflicts) { conflict in
                        conflictRow(conflict)
                    }
                }
            }
        } trailing: {
            if !conflicts.isEmpty {
                Text("\(conflicts.count)")
                    .font(DS.FontToken.bodyStrong.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.statusDanger)
            }
        }
    }

    /// Tapping a conflict opens the existing event editor on its first event.
    private func conflictRow(_ conflict: SchedulingIntelligence.EventConflict) -> some View {
        Button {
            editorTarget = WeekEditorTarget(eventID: conflict.first.id)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Circle()
                    .fill(DS.ColorToken.statusDanger)
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(conflict.first.title) ↔ \(conflict.second.title)")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(2)
                    Text(
                        "Overlap \(WeekEventBlock.timeFormatter.string(from: conflict.overlap.start)) – "
                            + WeekEventBlock.timeFormatter.string(from: conflict.overlap.end)
                    )
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open conflicting event \(conflict.first.title)")
    }

    // MARK: - Suggested Focus Blocks

    @ViewBuilder
    private var focusBlocksCard: some View {
        LiquidGlassCard("Suggested Focus Blocks") {
            if focusGaps.isEmpty {
                inspectorEmptyLine("No free focus gaps left in today's workday.")
            } else {
                VStack(spacing: DS.Space.s) {
                    ForEach(focusGaps.prefix(Self.maxFocusGapRows), id: \.start) { gap in
                        focusGapRow(gap)
                    }
                }
            }
        }
    }

    /// "Schedule" places the top unscheduled task into the gap through the
    /// SAME manual-block seam the strip and ManualBlockView use.
    private func focusGapRow(_ gap: DateInterval) -> some View {
        HStack(spacing: DS.Space.s) {
            Circle()
                .fill(DS.ColorToken.accentBlue)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    "\(WeekEventBlock.timeFormatter.string(from: gap.start)) – "
                        + WeekEventBlock.timeFormatter.string(from: gap.end)
                )
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                Text(WeekDurationText.text(for: gap.duration) + " free")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            Spacer(minLength: DS.Space.s)
            Button("Schedule") {
                scheduleTopTask(into: gap)
            }
            .buttonStyle(.plain)
            .font(DS.FontToken.caption)
            .foregroundStyle(
                unscheduledTasks.isEmpty ? DS.ColorToken.textMuted : DS.ColorToken.accentPrimaryHover
            )
            .disabled(unscheduledTasks.isEmpty)
            .accessibilityLabel("Schedule top unscheduled task into this gap")
        }
    }

    private func scheduleTopTask(into gap: DateInterval) {
        guard !LiquidReferenceMode.isEnabled else { return }
        guard let task = viewModel.unscheduledTasks.first else { return }
        let duration = WeekUnscheduledLoader.clampDuration(estimate: task.estimatedSeconds, gap: gap)
        _Concurrency.Task { @MainActor in
            await viewModel.addManualBlock(
                taskID: task.id,
                title: task.title,
                start: gap.start,
                end: gap.start.addingTimeInterval(duration)
            )
            viewModel.reloadUnscheduledTasks()
        }
    }

    // MARK: - Quick Reschedule

    /// One-tap move of a conflict's second event into the next free workday
    /// gap that fits it, through the EXISTING `updateEvent` seam. Rendered
    /// only when conflicts exist and the calendar is writable.
    private var quickRescheduleCard: some View {
        LiquidGlassCard("Quick Reschedule") {
            VStack(spacing: DS.Space.s) {
                ForEach(conflicts) { conflict in
                    quickRescheduleRow(conflict)
                }
            }
        }
    }

    @ViewBuilder
    private func quickRescheduleRow(_ conflict: SchedulingIntelligence.EventConflict) -> some View {
        let event = conflict.second
        let duration = event.end.timeIntervalSince(event.start)
        let gap = WeekIntelligence.nextFitGap(
            after: max(event.end, now()),
            duration: duration,
            events: intelligenceEvents,
            days: intelligenceDays,
            calendar: calendar
        )
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                if let gap {
                    Text("Next free: \(Self.gapLabelFormatter.string(from: gap.start))")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                } else {
                    Text("No free slot this week.")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }
            Spacer(minLength: DS.Space.s)
            if let gap {
                Button("Move") {
                    reschedule(eventID: event.id, to: gap)
                }
                .buttonStyle(.plain)
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.accentPrimaryHover)
                .accessibilityLabel("Move \(event.title) to the next free gap")
            }
        }
    }

    private func reschedule(eventID: String, to gap: DateInterval) {
        guard !LiquidReferenceMode.isEnabled else { return }
        guard var draft = viewModel.draft(forEventID: eventID, calendars: availableCalendars) else { return }
        draft.start = gap.start
        draft.end = gap.end
        _Concurrency.Task { @MainActor in
            await viewModel.updateEvent(id: eventID, draft: draft)
        }
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let gapLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    // MARK: - Time Insights

    @ViewBuilder
    private var timeInsightsCard: some View {
        let mirrored = mirroredEventIDs
        let insights = SchedulingIntelligence.timeInsights(
            events: intelligenceEvents,
            week: weekWindow,
            classify: { WeekEventClassifier.category(for: $0, mirroredEventIDs: mirrored) }
        )
        LiquidGlassCard("Time Insights") {
            if insights.totalScheduled == 0 {
                inspectorEmptyLine("Nothing scheduled this week yet.")
            } else {
                VStack(spacing: DS.Space.s) {
                    ForEach(Self.insightOrder, id: \.self) { category in
                        let total = insights.total(for: category)
                        if total > 0 {
                            insightRow(
                                label: WeekEventClassifier.label(for: category),
                                color: WeekEventClassifier.kind(for: category).accent,
                                seconds: total
                            )
                        }
                    }
                    LiquidDividerLine()
                    HStack {
                        Text("Total scheduled")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        Spacer()
                        Text(WeekDurationText.text(for: insights.totalScheduled))
                            .font(DS.FontToken.bodyStrong.monospacedDigit())
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                }
            }
        }
    }

    private static let insightOrder: [SchedulingIntelligence.EventCategory] = [
        .meeting, .focus, .project, .personal, .admin, .other,
    ]

    private func insightRow(label: String, color: Color, seconds: TimeInterval) -> some View {
        HStack(spacing: DS.Space.s) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(label)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Spacer()
            Text(WeekDurationText.text(for: seconds))
                .font(DS.FontToken.body.monospacedDigit())
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
    }
}
