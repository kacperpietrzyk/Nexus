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
                viewModel: calendarViewModel,
                onAddTask: {
                    NotificationCenter.default.post(name: .nexusOpenCapture, object: CapturePane.Mode.task)
                }
            )
            // Pin the view's structural identity so `destinationMain` branch
            // re-evaluations never tear down the screen's internal @State.
            .id(TodayNavSelection.calendar)
        } else {
            Color.clear
                .onAppear {
                    #if canImport(EventKit) && !os(watchOS)
                    let provider = EventKitCalendarProvider.shared
                    let viewModel = CalendarViewModel(
                        context: modelContext,
                        reader: provider,
                        writer: provider,
                        listing: provider
                    )
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
}
