import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// An event opened in the shared editor — either an existing external event
/// (edit/delete) or a brand-new draft (create). Shared by the main column and
/// the inspector, each presenting its own sheet over the same seam.
struct WeekEditorTarget: Identifiable, Equatable {
    enum Mode: Equatable {
        /// A new event; `seed` pre-fills its start/end when the user opened the
        /// editor from a specific empty slot (nil ⇒ the editor's own defaults).
        case create(seed: EventDraft?)
        case edit(eventID: String)
    }

    let mode: Mode

    /// Stable identity per presentation: the event id for edits, a fresh token
    /// per create so re-tapping "+" reliably re-presents the sheet.
    let id: String

    static func edit(_ eventID: String) -> WeekEditorTarget {
        WeekEditorTarget(mode: .edit(eventID: eventID), id: "edit-\(eventID)")
    }

    static func create(seed: EventDraft? = nil) -> WeekEditorTarget {
        WeekEditorTarget(mode: .create(seed: seed), id: "create-\(UUID().uuidString)")
    }

    /// Pure seam (unit-tested): the seed draft for "create at this slot" — the
    /// tapped start plus a default-duration end, on no system calendar yet
    /// (the editor's calendar picker, seeded from `preferredCalendarID`, owns
    /// the target). Title is left blank for the user to fill in.
    static func createSeed(
        at start: Date,
        duration: TimeInterval = WeekGridMetrics.defaultBlockDuration
    ) -> EventDraft {
        EventDraft(
            calendarID: nil,
            title: "",
            start: start,
            end: start.addingTimeInterval(duration)
        )
    }
}

extension View {
    /// The shared event-editor seam (`EventEditorView` over
    /// `CalendarViewModel.createEvent/draft/updateEvent/deleteEvent`), packaged
    /// so both `LiquidWeekScreen` and `SchedulingInspector` mount identical
    /// wiring for create and edit.
    func weekEventEditorSheet(
        target: Binding<WeekEditorTarget?>,
        viewModel: CalendarViewModel,
        calendars: [CalendarInfo]
    ) -> some View {
        sheet(item: target) { editorTarget in
            switch editorTarget.mode {
            case .create(let seed):
                EventEditorView(
                    mode: .create,
                    calendars: calendars,
                    initial: seed,
                    // #7: seed the new event's calendar from the configured
                    // write target (same as the iOS create path).
                    preferredCalendarID: viewModel.preferences.writeCalendarID,
                    onSave: { draft, _ in
                        _Concurrency.Task { @MainActor in
                            _ = await viewModel.createEvent(draft)
                            target.wrappedValue = nil
                        }
                    },
                    onCancel: { target.wrappedValue = nil }
                )
            case .edit(let eventID):
                EventEditorView(
                    mode: .edit(eventID: eventID),
                    calendars: calendars,
                    initial: viewModel.draft(forEventID: eventID, calendars: calendars),
                    onSave: { draft, span in
                        _Concurrency.Task { @MainActor in
                            await viewModel.updateEvent(id: eventID, draft: draft, span: span)
                            target.wrappedValue = nil
                        }
                    },
                    onDelete: { span in
                        _Concurrency.Task { @MainActor in
                            await viewModel.deleteEvent(id: eventID, span: span)
                            target.wrappedValue = nil
                        }
                    },
                    onCancel: { target.wrappedValue = nil }
                )
            }
        }
    }
}

/// The liquid Calendar page (Task 6, `docs/06_MODULE_CALENDAR.md`): serif
/// week-range header with Day/Week/Month switching + week navigation, then —
/// for Week/Day — the custom `WeekGrid` (grid fills the full frame; scheduling
/// intelligence + Unscheduled Tasks live in `SchedulingInspector`). Month
/// re-mounts the EXISTING `LiquidMonthGrid` under the same header.
///
/// All data is REAL: events/blocks come from the shared `CalendarViewModel`
/// (EventKit reader + `ScheduledBlockRepository`), unscheduled tasks from the
/// `TodayQuery.noDate()` bucket, and every scheduling action routes through
/// the existing `addManualBlock` (accepted block + mirror event) seam.
public struct LiquidWeekScreen: View {

    // `viewModel`, `editorTarget`, `availableCalendars`, and `undo` are internal
    // (not `private`) so the same-type context-menu dispatch lives in
    // `LiquidWeekScreen+ContextActions.swift` (keeps this file under length limits).
    @Bindable var viewModel: CalendarViewModel
    private let calendar: Calendar
    private let now: () -> Date
    /// App-layer capture seam for the strip's empty-state CTA (same
    /// notification path the Today screen uses); nil hides the CTA.
    private let onAddTask: (() -> Void)?

    @State var editorTarget: WeekEditorTarget?
    @State private var manualBlockRequest: ManualBlockRequest?
    @State var availableCalendars: [CalendarInfo] = []
    @State var undo = UndoController()

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
        // Bottom intentionally excluded: the grid fills the frame bottom to
        // align with the sidebar's bottom edge (both are inset from the window
        // edge by shellOuterVerticalPadding = 12 pt in LiquidAppShell). Adding
        // DS.Space.l (16 pt) here would raise the grid's baseline above the
        // sidebar's. Top + horizontal keep the header and banner insets intact.
        .padding([.top, .horizontal], DS.Space.l)
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
        .undoToast(undo)
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
                // Matches the iOS `CalendarView` pattern: the create affordance
                // only shows once access is granted (the access banner already
                // drives the grant prompt otherwise).
                if viewModel.hasCalendarAccess {
                    LiquidIconButton(
                        systemImage: "plus",
                        accessibilityLabel: "New event",
                        action: { editorTarget = .create() }
                    )
                }
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
        .liquidLightCard(cornerRadius: DS.Radius.m)
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
        .liquidLightCard(cornerRadius: DS.Radius.m)
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
        .liquidLightCard(cornerRadius: DS.Radius.m)
    }

    // MARK: - Content per scope

    @ViewBuilder
    private var content: some View {
        switch viewModel.scope {
        case .week:
            let reference =
                LiquidReferenceMode.isEnabled
                ? LiquidWeekReferenceData.snapshot(days: viewModel.visibleDays, now: now(), calendar: calendar)
                : nil
            WeekGrid(
                days: reference?.days ?? viewModel.visibleDays,
                calendar: calendar,
                now: now(),
                itemsForDay: { day in
                    if let reference {
                        return reference.itemsByDay[calendar.startOfDay(for: day)] ?? []
                    }
                    return weekItems(forDay: day)
                },
                onTapItem: { item in
                    guard reference == nil else { return }
                    handleTap(item)
                },
                onDropTask: { taskID, start in
                    guard reference == nil else { return }
                    _Concurrency.Task { await schedule(taskID: taskID, at: start) }
                },
                onCreateAt: { start in
                    guard reference == nil else { return }
                    createEvent(at: start)
                },
                onContextAction: { item, action in
                    guard reference == nil else { return }
                    handleContextAction(item: item, action: action)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Grid fills the full available height; scheduling intelligence +
            // Unscheduled Tasks live in SchedulingInspector (right panel).
            // Clipped so the rounded-card shape stays tight.
            .clipped()
            .layoutPriority(1)
        case .day:
            // Day = a single-column WeekGrid, so it inherits the exact Liquid
            // styling (glass card, hour axis, current-time line) instead of the
            // legacy NexusColor `DayGridView` (still used by the iOS
            // CalendarView, so left untouched).
            let dayReference =
                LiquidReferenceMode.isEnabled
                ? LiquidWeekReferenceData.snapshot(days: [viewModel.anchor], now: now(), calendar: calendar)
                : nil
            WeekGrid(
                days: [viewModel.anchor],
                calendar: calendar,
                now: now(),
                itemsForDay: { day in
                    if let dayReference {
                        return dayReference.itemsByDay[calendar.startOfDay(for: day)] ?? []
                    }
                    return weekItems(forDay: day)
                },
                onTapItem: { item in
                    guard dayReference == nil else { return }
                    handleTap(item)
                },
                onDropTask: { taskID, start in
                    guard dayReference == nil else { return }
                    _Concurrency.Task { await schedule(taskID: taskID, at: start) }
                },
                onCreateAt: { start in
                    guard dayReference == nil else { return }
                    createEvent(at: start)
                },
                onContextAction: { item, action in
                    guard dayReference == nil else { return }
                    handleContextAction(item: item, action: action)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        case .month:
            // Liquid-native month grid (glass card + DS tokens), not the legacy
            // NexusColor `MonthGridView` still used by the iOS CalendarView.
            LiquidMonthGrid(
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
        editorTarget = .edit(String(item.id.dropFirst("event-".count)))
    }

    /// Empty-slot tap (Day/Week grid): open the editor on a new event seeded at
    /// the tapped 15-min slot, routing through `createEvent` on save. Gated on
    /// access (matches the iOS create path) so an empty-slot tap can't lead to a
    /// guaranteed permission failure while the access banner is still prompting.
    private func createEvent(at start: Date) {
        guard viewModel.hasCalendarAccess else { return }
        editorTarget = .create(seed: WeekEditorTarget.createSeed(at: start))
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
