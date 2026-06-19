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
    ///
    /// Returns at most 2 suggestions, each ≤2 h, with starts rounded UP to the
    /// next whole hour — so "now = 10:57" yields 11:00–13:00, not 10:57–12:57.
    /// A few clean round-hour windows read better than slicing the whole
    /// afternoon into N consecutive 2 h blocks.
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
        let clampedStart = max(window.start, now)
        guard clampedStart < window.end else { return [] }
        // Round the search start UP to the next whole hour so suggestions
        // begin at clean times. If clampedStart is already on the hour, no-op.
        let searchStart = ceilToHour(clampedStart, calendar: calendar)
        guard searchStart < window.end else { return [] }
        let raw = SchedulingIntelligence.suggestedFocusBlocks(
            events: events,
            within: DateInterval(start: searchStart, end: window.end),
            // 2 h per block — an empty workday must not read as one 10 h slab.
            maximumDuration: 2 * 3600
        )
        // Cap to 2 suggestions — a "few" clean windows, not the whole afternoon.
        return Array(raw.prefix(2))
    }

    /// Rounds `date` up to the start of the next whole hour. If `date` is
    /// already exactly on the hour, returns it unchanged.
    static func ceilToHour(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard
            let minute = components.minute,
            let second = components.second,
            minute != 0 || second != 0
        else { return date }
        // Truncate to the current hour then add one hour.
        var truncated = components
        truncated.minute = 0
        truncated.second = 0
        truncated.nanosecond = 0
        guard
            let hourStart = calendar.date(from: truncated),
            let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart)
        else { return date }
        return nextHour
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

    /// Enumerates every calendar day that starts within `range` (inclusive of
    /// `range.start`, exclusive of `range.end`). Used to scope meeting-load
    /// over the stats interval rather than over `visibleDays`, which for month
    /// scope is the 42-day grid rather than the calendar month.
    static func daysIn(_ range: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: range.start)
        while cursor < range.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}

/// The Calendar right inspector (304 pt slot, `docs/06_MODULE_CALENDAR.md`
/// §Right inspector): unified 4-section scheduling intelligence panel —
/// Stats, Conflicts (with inline Move), Focus, Unscheduled Tasks — identical
/// structure across Day/Week/Month; Conflicts and Focus hide when empty;
/// Unscheduled fills the remaining height with its own scroll so a long list
/// scrolls independently without pushing the fixed cards off-screen.
public struct SchedulingInspector: View {

    private let viewModel: CalendarViewModel
    private let calendar: Calendar
    private let now: () -> Date

    @State private var editorTarget: WeekEditorTarget?
    @State private var availableCalendars: [CalendarInfo] = []

    /// Spec §Meeting Load mirrors the Today Focus Timer ring scale (62–70 pt).
    private static let ringSize: CGFloat = 66

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
        // Two-region layout: fixed cards (Stats, Conflicts, Focus) stay at
        // natural height at the top; the Unscheduled section fills the
        // remaining height with its own internal ScrollView so a long task list
        // scrolls independently without pushing the fixed cards off-screen.
        VStack(spacing: DS.Space.m) {
            // Fixed-height upper region: only Stats is always present;
            // Conflicts and Focus hide entirely when empty.
            VStack(spacing: DS.Space.m) {
                statsCard
                if !conflicts.isEmpty {
                    conflictsCard
                }
                if !focusGaps.isEmpty {
                    focusBlocksCard
                }
            }
            // Unscheduled Tasks: present in all scopes (Day/Week/Month) so
            // drag-to-schedule works everywhere. Fills remaining height.
            unscheduledCard
                .frame(maxHeight: .infinity, alignment: .top)
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

    /// The stats interval for the current scope+anchor — determines what range
    /// the Stats card covers and what label it shows.
    private var statsRange: DateInterval {
        SchedulingIntelligence.statsRange(
            scope: viewModel.scope,
            anchor: viewModel.anchor,
            calendar: calendar
        )
    }

    /// "Today" / "This week" / "This month" — follows scope.
    private var statsLabel: String {
        switch viewModel.scope {
        case .day: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        }
    }

    /// Meeting load computed over the scope-scoped stats interval (not over
    /// `intelligenceDays`, which for month is a 42-day grid).
    private var statsMeetingLoad: Double {
        let days = WeekIntelligence.daysIn(statsRange, calendar: calendar)
        return WeekIntelligence.weekMeetingLoad(
            events: intelligenceEvents,
            days: days,
            calendar: calendar,
            mirroredEventIDs: mirroredEventIDs
        )
    }

    /// Time insights computed over the scope-scoped stats interval.
    private var statsInsights: SchedulingIntelligence.TimeInsights {
        let mirrored = mirroredEventIDs
        return SchedulingIntelligence.timeInsights(
            events: intelligenceEvents,
            week: statsRange,
            classify: { WeekEventClassifier.category(for: $0, mirroredEventIDs: mirrored) }
        )
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

    // MARK: - Stats (merged Meeting Load + Time Insights)

    /// Unified stats card: meeting-load ring + total-scheduled / in-meetings
    /// hour lines. Scope label ("Today" / "This week" / "This month") and the
    /// computed interval both follow `viewModel.scope` + `viewModel.anchor`.
    private var statsCard: some View {
        LiquidGlassCard(statsLabel) {
            VStack(spacing: DS.Space.m) {
                // Meeting-load ring row
                HStack(spacing: DS.Space.m) {
                    LiquidCircularProgress(
                        value: statsMeetingLoad,
                        title: "\(Int((statsMeetingLoad * 100).rounded()))%",
                        size: Self.ringSize,
                        color: DS.ColorToken.accentPurple
                    )
                    Text("of workday hours are in meetings.")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                // Hour lines: total scheduled + in meetings
                if statsInsights.totalScheduled > 0 {
                    LiquidDividerLine()
                    HStack {
                        Text("Total scheduled")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                        Spacer()
                        Text(WeekDurationText.text(for: statsInsights.totalScheduled))
                            .font(DS.FontToken.body.monospacedDigit())
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                    let meetingTotal = statsInsights.total(for: .meeting)
                    if meetingTotal > 0 {
                        HStack {
                            Text("In meetings")
                                .font(DS.FontToken.metadata)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                            Spacer()
                            Text(WeekDurationText.text(for: meetingTotal))
                                .font(DS.FontToken.body.monospacedDigit())
                                .foregroundStyle(DS.ColorToken.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Conflicts

    /// Conflicts card: hidden when zero conflicts. Each conflict row has an
    /// inline [Move] button that targets the next-fit gap — the standalone
    /// Quick Reschedule card has been folded into this section.
    private var conflictsCard: some View {
        LiquidGlassCard("Conflicts") {
            VStack(spacing: DS.Space.s) {
                ForEach(conflicts) { conflict in
                    conflictRow(conflict)
                }
            }
        } trailing: {
            Text("\(conflicts.count)")
                .font(DS.FontToken.bodyStrong.monospacedDigit())
                .foregroundStyle(DS.ColorToken.statusDanger)
        }
    }

    /// Conflict row: tapping the title region opens the editor; the trailing
    /// [Move] button reschedules the second event to the next free gap.
    /// The two interactions are separate tap targets so they do not nest.
    private func conflictRow(_ conflict: SchedulingIntelligence.EventConflict) -> some View {
        let event = conflict.second
        let duration = event.end.timeIntervalSince(event.start)
        let gap = WeekIntelligence.nextFitGap(
            after: max(event.end, now()),
            duration: duration,
            events: intelligenceEvents,
            days: intelligenceDays,
            calendar: calendar
        )
        return HStack(alignment: .top, spacing: DS.Space.s) {
            // Tappable text region — opens the editor on the first event.
            Button {
                editorTarget = .edit(conflict.first.id)
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
                        if let gap {
                            Text("Next free: \(Self.gapLabelFormatter.string(from: gap.start))")
                                .font(DS.FontToken.metadata)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open conflicting event \(conflict.first.title)")

            Spacer(minLength: DS.Space.s)

            // Inline Move button — reschedules the second event; only shown
            // when a free slot exists and the calendar is writable.
            if let gap, viewModel.hasCalendarAccess || LiquidReferenceMode.isEnabled {
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

    // MARK: - Focus

    /// Focus card: "Today's focus" — at most 2 round-hour 2 h gaps in today's
    /// workday. Hidden entirely when no gaps remain.
    private var focusBlocksCard: some View {
        LiquidGlassCard("Today's focus") {
            VStack(spacing: DS.Space.s) {
                ForEach(focusGaps, id: \.start) { gap in
                    focusGapRow(gap)
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

    // MARK: - Unscheduled Tasks (4th section, drag source)

    /// Unscheduled Tasks section: present in all scopes (Day/Week/Month) so
    /// rows are always available as drag sources for the grid drop targets.
    /// The card fills remaining height; its content scrolls independently so a
    /// long list never pushes Stats/Conflicts/Focus off-screen.
    private var unscheduledCard: some View {
        LiquidGlassCard("Unscheduled Tasks") {
            if unscheduledTasks.isEmpty {
                inspectorEmptyLine("Every open task has a date or a scheduled block.")
            } else {
                // ScrollView scoped to the card interior: the list scrolls
                // within the card bounds, not the whole inspector.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Space.xxs) {
                        ForEach(unscheduledTasks) { task in
                            unscheduledTaskRow(task)
                        }
                    }
                }
            }
        } trailing: {
            if !unscheduledTasks.isEmpty {
                Text("\(unscheduledTasks.count)")
                    .font(DS.FontToken.metadata.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
    }

    /// A single draggable task row. The `.onDrag` payload is the task UUID as
    /// a plain string (Task 11 reads this contract from the grid drop target).
    private func unscheduledTaskRow(_ task: WeekUnscheduledTask) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
                .accessibilityHidden(true)
            Text(task.title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineLimit(1)
            if let projectName = task.projectName {
                LiquidPill(projectName, color: DS.ColorToken.accentCyan)
            }
            Spacer(minLength: DS.Space.s)
            if let seconds = task.estimatedSeconds, seconds > 0 {
                Text(WeekDurationText.text(for: TimeInterval(seconds)))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: 28)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
        .accessibilityLabel("Unscheduled task: \(task.title)")
    }

}
