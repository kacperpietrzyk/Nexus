import CalendarFeature
import NexusCore
import SwiftUI
import TasksFeature

// Liquid Calendar / Week Planning composition (Task 6), extracted out of
// `ContentView` (file-length budget) alongside the Today extension. The same
// lazily-built `CalendarViewModel` (live container + shared EventKit provider)
// drives BOTH the main column (`LiquidWeekScreen`) and the right-inspector
// slot (`SchedulingInspector`), so grid, strip, and intelligence cards render
// one load.
extension ContentView {

    /// The Liquid Calendar main column, mounted by `destinationMain` for
    /// `.calendar`.
    @ViewBuilder
    var liquidCalendarMain: some View {
        if let calendarViewModel {
            LiquidWeekScreen(
                viewModel: calendarViewModel
            )
            // Pin the view's structural identity so `destinationMain` branch
            // re-evaluations never tear down the screen's internal @State.
            .id(TodayNavSelection.calendar)
            // Task 10: Month→Day drill breadcrumb. Observe scope changes on the
            // @Observable CalendarViewModel. When the user taps a day from Month
            // scope, scope transitions Month→Day; we record that and publish a
            // detail crumb. Any exit from Day scope (user taps Week/Month in the
            // segmented control) clears the flag and crumb.
            .onChange(of: calendarViewModel.scope) { oldScope, newScope in
                if oldScope == .month && newScope == .day {
                    calendarDrilledFromMonth = true
                } else if newScope != .day {
                    calendarDrilledFromMonth = false
                }
                updateCalendarCrumb(viewModel: calendarViewModel)
            }
            // When anchor changes while drilled (user navigates to a different
            // day), refresh the crumb label.
            .onChange(of: calendarViewModel.anchor) { _, _ in
                if calendarDrilledFromMonth {
                    updateCalendarCrumb(viewModel: calendarViewModel)
                }
            }
            .onAppear {
                // onPopToRoot: "Calendar" ancestor in the breadcrumb → return
                // to Month and clear the drill state.
                navigator.onPopToRoot = {
                    calendarViewModel.scope = .month
                    // scope onChange fires and clears flag+crumb, but be explicit
                    // to avoid a frame gap.
                    calendarDrilledFromMonth = false
                    navigator.detailCrumb = nil
                }
                // Re-derive crumb if returning to Calendar while still drilled.
                updateCalendarCrumb(viewModel: calendarViewModel)
            }
        } else {
            Color.clear
                .onAppear {
                    #if canImport(EventKit) && !os(watchOS)
                    let provider = EventKitCalendarProvider.shared
                    #if DEBUG
                    // When calendar access has not been granted (common in dev
                    // builds), inject the sample provider so the grid is
                    // populated and every later visual task is clickable without
                    // needing real EventKit data. When access IS granted the
                    // live provider is used verbatim; behavior is unchanged.
                    let status = provider.authorizationStatus()
                    let hasAccess = status == .fullAccess || status == .writeOnly
                    let reader: any CalendarEventProviding =
                        hasAccess ? provider : CalendarSampleProvider()
                    let isLive = reader is EventKitCalendarProvider
                    let viewModel = CalendarViewModel(
                        context: modelContext,
                        reader: reader,
                        writer: isLive ? provider : nil,
                        listing: isLive ? provider : nil,
                        changes: isLive ? provider : nil
                    )
                    #else
                    let viewModel = CalendarViewModel(
                        context: modelContext,
                        reader: provider,
                        writer: provider,
                        listing: provider,
                        changes: provider
                    )
                    #endif
                    // The liquid Calendar page IS the Week planner (Task 6);
                    // Day/Month remain reachable via the segmented control.
                    viewModel.scope = .week
                    calendarViewModel = viewModel
                    #endif
                }
        }
    }

    /// Right-inspector slot content for `.calendar` (Scheduling Intelligence,
    /// 304 pt); `nil` everywhere else so the column disappears entirely.
    var calendarInspectorSlot: (() -> AnyView)? {
        guard selection == .calendar, let viewModel = calendarViewModel else { return nil }
        return {
            AnyView(SchedulingInspector(viewModel: viewModel))
        }
    }

    // MARK: - Task 10: Month→Day breadcrumb helpers

    /// Publishes or clears `navigator.detailCrumb` based on whether the user
    /// is currently in a Month→Day drill. Terminal write — nothing observes
    /// `detailCrumb` to write back to scope/anchor, so the update is loop-free.
    func updateCalendarCrumb(viewModel: CalendarViewModel) {
        if calendarDrilledFromMonth {
            navigator.detailCrumb = NavCrumb(
                id: "calday:\(viewModel.anchor.timeIntervalSince1970)",
                label: Self.calendarCrumbFormatter.string(from: viewModel.anchor),
                isLeaf: true
            )
        } else {
            navigator.detailCrumb = nil
        }
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL), matching
    /// the `LiquidToolbar` date formatter idiom. Format: "Sat, Jun 14".
    static let calendarCrumbFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}
