import NexusCore
import NexusUI
import SwiftUI

/// The calendar surface entry point (spec §9): scope switcher, period navigation,
/// "Plan my day" + "Accept all", and the Day/Week/Month grids. No-access shows an
/// empty state + CTA (spec §13). Mac / iPad / iPhone (the grids are responsive).
public struct CalendarView: View {
    @State private var viewModel: CalendarViewModel
    @State private var editorContext: EditorContext?
    @State private var availableCalendars: [CalendarInfo] = []

    private let calendar: Calendar
    private let now: () -> Date

    public init(
        viewModel: CalendarViewModel,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        _viewModel = State(initialValue: viewModel)
        self.calendar = calendar
        self.now = now
    }

    private enum EditorContext: Identifiable {
        case create
        case editEvent(eventID: String)
        case manualBlock
        case settings

        var id: String {
            switch self {
            case .create: return "create"
            case .editEvent(let eventID): return "edit-\(eventID)"
            case .manualBlock: return "manual-block"
            case .settings: return "settings"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NexusColor.Line.hairline)
            content
        }
        .background(NexusColor.Background.base)
        .task {
            await viewModel.load()
            availableCalendars = await viewModel.availableCalendars()
        }
        .onChange(of: viewModel.scope) { _, _ in Task { await viewModel.load() } }
        .onChange(of: viewModel.anchor) { _, _ in Task { await viewModel.load() } }
        .sheet(item: $editorContext) { context in
            sheetContent(for: context)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(periodLabel)
                    .font(NexusType.h2)
                    .foregroundStyle(NexusColor.Text.primary)
                Spacer()
                navButtons
            }
            HStack(spacing: 8) {
                scopePicker
                Spacer()
                if viewModel.hasCalendarAccess {
                    actionButtons
                }
            }
            if let overload = viewModel.overload, overload.isOverloaded {
                overloadBanner(overload)
            }
            if let notice = viewModel.planNotice {
                planNoticeBanner(notice)
            }
        }
        .padding(14)
    }

    private func planNoticeBanner(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(NexusColor.Text.muted)
            Text(notice)
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.secondary)
            Spacer()
        }
        .padding(8)
        .background(NexusColor.Background.panel, in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
    }

    private var navButtons: some View {
        HStack(spacing: 6) {
            iconButton("chevron.left", label: "Previous") { viewModel.step(-1) }
            NexusButton(variant: .outline, size: .sm) {
                viewModel.goToToday()
            } label: {
                Text("Today")
            }
            .accessibilityLabel("Go to today")
            iconButton("chevron.right", label: "Next") { viewModel.step(1) }
        }
    }

    private var scopePicker: some View {
        NexusSegmentedControl(
            items: CalendarScope.allCases.map { NexusSegmentedItem(id: $0, label: $0.label) },
            selection: $viewModel.scope
        )
        .frame(maxWidth: 240)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button("Plan my day") {
                Task { await viewModel.planDay() }
            }
            .buttonStyle(.plain)
            .font(NexusType.bodySmall.weight(.semibold))
            .foregroundStyle(NexusColor.Accent.limeInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(NexusColor.Accent.lime, in: Capsule())

            if hasProposals {
                Button("Accept all") {
                    Task { await viewModel.acceptAll() }
                }
                .buttonStyle(.plain)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(NexusColor.Background.control, in: Capsule())
            }

            iconButton("plus", label: "New event") { editorContext = .create }
            iconButton("rectangle.stack.badge.plus", label: "Add block") { editorContext = .manualBlock }
            iconButton("gearshape", label: "Calendar settings") { editorContext = .settings }
        }
    }

    private func overloadBanner(_ overload: OverloadReport) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NexusColor.Status.danger)
            Text("Overloaded — \(overload.unplacedTaskIDs.count) task(s) didn't fit today.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.secondary)
            Spacer()
        }
        .padding(8)
        .background(NexusColor.Background.panel, in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasCalendarAccess {
            noAccessState
        } else {
            switch viewModel.scope {
            case .day:
                DayGridView(
                    day: viewModel.anchor,
                    items: viewModel.timelineItems(forDay: viewModel.anchor),
                    calendar: calendar,
                    now: now(),
                    onAccept: { id in Task { await viewModel.accept(blockID: id) } },
                    onReject: { id in viewModel.reject(blockID: id) },
                    onTapItem: { handleTap($0) },
                    onAdjust: { id, start, end in
                        Task { await viewModel.adjust(blockID: id, start: start, end: end) }
                    }
                )
            case .week:
                WeekGridView(
                    days: viewModel.visibleDays,
                    calendar: calendar,
                    now: now(),
                    itemsForDay: { viewModel.timelineItems(forDay: $0) },
                    onAccept: { id in Task { await viewModel.accept(blockID: id) } },
                    onReject: { id in viewModel.reject(blockID: id) },
                    onTapItem: { handleTap($0) },
                    onSelectDay: { selectDay($0) }
                )
            case .month:
                MonthGridView(
                    days: viewModel.visibleDays,
                    anchor: viewModel.anchor,
                    calendar: calendar,
                    now: now(),
                    itemsForDay: { viewModel.timelineItems(forDay: $0) },
                    onSelectDay: { selectDay($0) }
                )
            }
        }
    }

    private var noAccessState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(NexusColor.Text.tertiary)
            Text("Calendar access needed")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.primary)
            Text("Grant access so Nexus can read your events and plan your day around them.")
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Grant access") {
                Task { await viewModel.requestAccess() }
            }
            .buttonStyle(.plain)
            .font(NexusType.bodySmall.weight(.semibold))
            .foregroundStyle(NexusColor.Accent.limeInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(NexusColor.Accent.lime, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for context: EditorContext) -> some View {
        switch context {
        case .create:
            EventEditorView(
                mode: .create,
                calendars: availableCalendars,
                // #7: seed the new event's calendar from the configured write target.
                preferredCalendarID: viewModel.preferences.writeCalendarID,
                onSave: { draft, _ in
                    Task {
                        _ = await viewModel.createEvent(draft)
                        editorContext = nil
                    }
                },
                onCancel: { editorContext = nil }
            )
        case .editEvent(let eventID):
            EventEditorView(
                mode: .edit(eventID: eventID),
                calendars: availableCalendars,
                initial: viewModel.draft(forEventID: eventID, calendars: availableCalendars),
                onSave: { draft, span in
                    Task {
                        await viewModel.updateEvent(id: eventID, draft: draft, span: span)
                        editorContext = nil
                    }
                },
                onDelete: { span in
                    Task {
                        await viewModel.deleteEvent(id: eventID, span: span)
                        editorContext = nil
                    }
                },
                onCancel: { editorContext = nil }
            )
        case .manualBlock:
            ManualBlockView(
                tasks: viewModel.schedulableTasks(),
                anchor: viewModel.anchor,
                onAdd: { taskID, title, start, end in
                    Task {
                        await viewModel.addManualBlock(taskID: taskID, title: title, start: start, end: end)
                        editorContext = nil
                    }
                },
                onCancel: { editorContext = nil }
            )
        case .settings:
            CalendarSettingsView(viewModel: viewModel)
        }
    }

    // MARK: - Helpers

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NexusColor.Text.secondary)
                .frame(width: 28, height: 28)
                .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func selectDay(_ day: Date) {
        viewModel.anchor = day
        viewModel.scope = .day
    }

    /// Tapping an external event opens the editor (edit/delete, spec §9). Tapping a
    /// block is a no-op — blocks carry inline accept/reject controls instead.
    private func handleTap(_ item: TimelineItem) {
        guard item.kind == .event else { return }
        // TimelineItem ids are "event-<eventID>"; recover the raw EventKit id.
        let eventID = String(item.id.dropFirst("event-".count))
        editorContext = .editEvent(eventID: eventID)
    }

    private var hasProposals: Bool {
        viewModel.blocks.contains { $0.status == .proposed }
    }

    private var periodLabel: String {
        switch viewModel.scope {
        case .day: return Self.dayFormatter.string(from: viewModel.anchor)
        case .week:
            let win = viewModel.window
            let endInclusive = calendar.date(byAdding: .day, value: -1, to: win.end) ?? win.end
            return "\(Self.shortFormatter.string(from: win.start)) – \(Self.shortFormatter.string(from: endInclusive))"
        case .month: return Self.monthFormatter.string(from: viewModel.anchor)
        }
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
