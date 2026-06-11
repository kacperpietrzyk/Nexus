import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// An external event opened in the existing editor (shared by the main column
/// and the inspector — each presents its own sheet over the same seam).
struct WeekEditorTarget: Identifiable, Equatable {
    let eventID: String
    var id: String { eventID }
}

extension View {
    /// The existing event-editor seam (`EventEditorView` over
    /// `CalendarViewModel.draft/updateEvent/deleteEvent`), packaged so both
    /// `LiquidWeekScreen` and `SchedulingInspector` mount identical wiring.
    func weekEventEditorSheet(
        target: Binding<WeekEditorTarget?>,
        viewModel: CalendarViewModel,
        calendars: [CalendarInfo]
    ) -> some View {
        sheet(item: target) { editorTarget in
            EventEditorView(
                mode: .edit(eventID: editorTarget.eventID),
                calendars: calendars,
                initial: viewModel.draft(forEventID: editorTarget.eventID, calendars: calendars),
                onSave: { draft, span in
                    _Concurrency.Task { @MainActor in
                        await viewModel.updateEvent(id: editorTarget.eventID, draft: draft, span: span)
                        target.wrappedValue = nil
                    }
                },
                onDelete: { span in
                    _Concurrency.Task { @MainActor in
                        await viewModel.deleteEvent(id: editorTarget.eventID, span: span)
                        target.wrappedValue = nil
                    }
                },
                onCancel: { target.wrappedValue = nil }
            )
        }
    }
}

/// The liquid Calendar page (Task 6, `docs/06_MODULE_CALENDAR.md`): serif
/// week-range header with Day/Week/Month switching + week navigation, then —
/// for Week — the custom `WeekGrid` over the bottom `SchedulingStrip`. Day and
/// Month re-mount the EXISTING `DayGridView`/`MonthGridView` under the same
/// header (smallest viable integration; those grids are not rebuilt).
///
/// All data is REAL: events/blocks come from the shared `CalendarViewModel`
/// (EventKit reader + `ScheduledBlockRepository`), unscheduled tasks from the
/// `TodayQuery.noDate()` bucket, and every scheduling action routes through
/// the existing `addManualBlock` (accepted block + mirror event) seam.
public struct LiquidWeekScreen: View {

    @Bindable private var viewModel: CalendarViewModel
    private let calendar: Calendar
    private let now: () -> Date
    /// App-layer capture seam for the strip's empty-state CTA (same
    /// notification path the Today screen uses); nil hides the CTA.
    private let onAddTask: (() -> Void)?

    @State private var editorTarget: WeekEditorTarget?
    @State private var manualBlockRequest: ManualBlockRequest?
    @State private var availableCalendars: [CalendarInfo] = []

    private struct ManualBlockRequest: Identifiable {
        let taskID: UUID
        var id: UUID { taskID }
    }

    public init(
        viewModel: CalendarViewModel,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        onAddTask: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.calendar = calendar
        self.now = now
        self.onAddTask = onAddTask
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            header
            if !viewModel.hasCalendarAccess {
                accessBanner
            }
            if let message = viewModel.lastError {
                errorRow(message)
            }
            if !viewModel.conflictedBlockIDs.isEmpty {
                conflictRow(count: viewModel.conflictedBlockIDs.count)
            }
            content
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.load()
            availableCalendars = await viewModel.availableCalendars()
            viewModel.reloadUnscheduledTasks()
        }
        .onChange(of: viewModel.scope) { _, _ in
            _Concurrency.Task { await viewModel.load() }
        }
        .onChange(of: viewModel.anchor) { _, _ in
            _Concurrency.Task { await viewModel.load() }
        }
        .weekEventEditorSheet(target: $editorTarget, viewModel: viewModel, calendars: availableCalendars)
        .sheet(item: $manualBlockRequest) { request in
            manualBlockSheet(request)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Text(periodTitle)
                .font(DS.FontToken.displayMedium)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineLimit(1)

            Spacer(minLength: DS.Space.m)

            LiquidSegmentedControl(
                options: CalendarScope.allCases.map { LiquidSegmentOption($0, label: $0.label) },
                selection: $viewModel.scope
            )

            HStack(spacing: DS.Space.xs) {
                LiquidIconButton(
                    systemImage: "chevron.left",
                    accessibilityLabel: "Previous \(viewModel.scope.label.lowercased())",
                    action: { viewModel.step(-1) }
                )
                todayButton
                LiquidIconButton(
                    systemImage: "chevron.right",
                    accessibilityLabel: "Next \(viewModel.scope.label.lowercased())",
                    action: { viewModel.step(1) }
                )
            }
        }
    }

    /// Text sibling of `LiquidIconButton` (same 30 pt glass chrome).
    private var todayButton: some View {
        Button {
            viewModel.goToToday()
        } label: {
            Text("Today")
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .padding(.horizontal, DS.Space.m)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(DS.ColorToken.glassSoft)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to today")
    }

    /// Real period title — e.g. "June 8 – June 14, 2026" for Week (spec
    /// §Header), following the active scope for Day/Month.
    private var periodTitle: String {
        switch viewModel.scope {
        case .day:
            return Self.dayTitleFormatter.string(from: viewModel.anchor)
        case .week:
            let window = viewModel.window
            let endInclusive = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
            return "\(Self.rangeStartFormatter.string(from: window.start)) – "
                + Self.rangeEndFormatter.string(from: endInclusive)
        case .month:
            return Self.monthTitleFormatter.string(from: viewModel.anchor)
        }
    }

    // MARK: - Access banner / errors

    /// The grid chrome renders regardless of calendar access (the screen must
    /// look correct with zero events); access is requested from this banner
    /// instead of replacing the page.
    private var accessBanner: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.statusWarning)
                .accessibilityHidden(true)
            Text("Calendar access needed — events can't be read or written yet.")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Spacer(minLength: DS.Space.s)
            LiquidPrimaryButton("Grant access") {
                _Concurrency.Task { await viewModel.requestAccess() }
            }
        }
        .padding(DS.Space.s)
        .liquidGlass(.card, radius: DS.Radius.m)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.statusWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s)
        .liquidGlass(.card, radius: DS.Radius.m)
    }

    /// M1 non-blocking conflict affordance (mirrors `errorRow` chrome):
    /// "Replan" tears the conflicted blocks down and re-proposes their tasks.
    private func conflictRow(count: Int) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.statusWarning)
                .accessibilityHidden(true)
            Text(CalendarViewModel.conflictNotice(count: count))
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Spacer(minLength: DS.Space.s)
            LiquidPrimaryButton("Replan") {
                _Concurrency.Task { await viewModel.replanConflicted() }
            }
            LiquidIconButton(
                systemImage: "xmark",
                accessibilityLabel: "Dismiss conflict notice",
                action: { viewModel.dismissConflicts() }
            )
        }
        .padding(DS.Space.s)
        .liquidGlass(.card, radius: DS.Radius.m)
    }

    // MARK: - Content per scope

    @ViewBuilder
    private var content: some View {
        switch viewModel.scope {
        case .week:
            WeekGrid(
                days: viewModel.visibleDays,
                calendar: calendar,
                now: now(),
                itemsForDay: { weekItems(forDay: $0) },
                onTapItem: { handleTap($0) },
                onDropTask: { taskID, start in
                    _Concurrency.Task { await schedule(taskID: taskID, at: start) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The grid dominates the page; the strip stays a fixed band
            // (04_LAYOUT_SYSTEM.md §Calendar Week — grid over a bottom strip).
            .layoutPriority(1)
            SchedulingStrip(
                tasks: viewModel.unscheduledTasks,
                focusGap: WeekIntelligence.todayFocusGaps(
                    events: viewModel.events,
                    days: viewModel.visibleDays,
                    calendar: calendar,
                    now: now()
                ).first,
                onScheduleTopTask: { gap in scheduleTopTask(into: gap) },
                onDropTaskToZone: { taskID in manualBlockRequest = ManualBlockRequest(taskID: taskID) },
                onAddTask: onAddTask
            )
            // Fixed strip band so the grid keeps the page (reference
            // proportions: strip ≈ 1/5 of the content column).
            .frame(height: 210)
        case .day:
            // Existing day grid re-mounted under the liquid header (same
            // handler wiring as the legacy CalendarView mount).
            DayGridView(
                day: viewModel.anchor,
                items: viewModel.timelineItems(forDay: viewModel.anchor),
                calendar: calendar,
                now: now(),
                onAccept: { id in _Concurrency.Task { await viewModel.accept(blockID: id) } },
                onReject: { id in viewModel.reject(blockID: id) },
                onTapItem: { handleTap($0) },
                onAdjust: { id, start, end in
                    _Concurrency.Task { await viewModel.adjust(blockID: id, start: start, end: end) }
                }
            )
        case .month:
            // Existing month grid re-mounted under the liquid header.
            MonthGridView(
                days: viewModel.visibleDays,
                anchor: viewModel.anchor,
                calendar: calendar,
                now: now(),
                itemsForDay: { viewModel.timelineItems(forDay: $0) },
                onSelectDay: { day in
                    viewModel.anchor = day
                    viewModel.scope = .day
                }
            )
        }
    }

    // MARK: - Week data

    /// Grid items for one day. Mirror events of accepted blocks are deduped
    /// out (the block itself renders, classified as focus) so a scheduled
    /// task never paints twice in the same column.
    private func weekItems(forDay day: Date) -> [TimelineItem] {
        let mirroredEventIDs = Set(viewModel.blocks.compactMap(\.externalEventID))
        let events = viewModel.events.filter { !mirroredEventIDs.contains($0.id) }
        return DayTimelineLayout.items(
            forDay: day,
            events: events,
            blocks: viewModel.blocks,
            calendar: calendar,
            conflictedBlockIDs: viewModel.conflictedBlockIDs,
            seriesPreviews: viewModel.seriesPreviews
        )
    }

    /// Tapping an external event opens the editor (spec §Interaction rules);
    /// block accept/reject stays on the Day grid's inline controls.
    private func handleTap(_ item: TimelineItem) {
        guard item.kind == .event else { return }
        editorTarget = WeekEditorTarget(eventID: String(item.id.dropFirst("event-".count)))
    }

    // MARK: - Scheduling actions (existing manual-block seam)

    /// Drop on the grid: schedule the task at the snapped slot for its own
    /// estimate (1 h default) via `addManualBlock` — the same accepted-block +
    /// mirror-event path `ManualBlockView` commits through.
    @MainActor
    private func schedule(taskID: UUID, at start: Date) async {
        guard let task = viewModel.unscheduledTasks.first(where: { $0.id == taskID }) else { return }
        let duration = task.estimatedSeconds.map(TimeInterval.init) ?? WeekGridMetrics.defaultBlockDuration
        await viewModel.addManualBlock(
            taskID: task.id,
            title: task.title,
            start: start,
            end: start.addingTimeInterval(duration)
        )
        viewModel.reloadUnscheduledTasks()
    }

    /// Focus-card CTA: top unscheduled task into the recommended gap, clamped
    /// to the gap.
    private func scheduleTopTask(into gap: DateInterval) {
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

    /// Drop-zone fallback: open the existing schedule affordance pre-selected
    /// with the dropped task (`ManualBlockView` selects the first list entry).
    private func manualBlockSheet(_ request: ManualBlockRequest) -> some View {
        var tasks = viewModel.schedulableTasks()
        if let index = tasks.firstIndex(where: { $0.id == request.taskID }) {
            tasks.insert(tasks.remove(at: index), at: 0)
        }
        return ManualBlockView(
            tasks: tasks,
            anchor: viewModel.anchor,
            onAdd: { taskID, title, start, end in
                _Concurrency.Task { @MainActor in
                    await viewModel.addManualBlock(taskID: taskID, title: title, start: start, end: end)
                    manualBlockRequest = nil
                    viewModel.reloadUnscheduledTasks()
                }
            },
            onCancel: { manualBlockRequest = nil }
        )
    }

    // MARK: - Formatters (English UI rule: explicit en_US)

    private static let rangeStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d"
        return formatter
    }()

    private static let rangeEndFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
