import NexusMeetings
import NexusUI
import SwiftUI
import TasksFeature

// Liquid Meetings / Notes Intelligence composition (Task 10), extracted out
// of `ContentView` (file-length budget) alongside the Today / Calendar /
// Projects extensions. One shared `LiquidMeetingsModel` (`@State` on
// `ContentView`) drives BOTH the main column (`LiquidMeetingsScreen`: list +
// detail + knowledge column) and the right-inspector slot
// (`MeetingActionsInspector`) — the same one-model/two-slots sharing shape.
// Selection rides the existing `MeetingNavigationRouter` (env-injected), so
// agent/notification deep-links into a meeting keep working unchanged.
extension ContentView {

    /// The Liquid Meetings main column, mounted by `destinationMain` for
    /// `.meetings`.
    @ViewBuilder
    var liquidMeetingsMain: some View {
        if let meetingsComposition, let meetingNavigationRouter {
            LiquidMeetingsScreen(
                model: liquidMeetingsModel,
                composition: meetingsComposition,
                router: meetingNavigationRouter,
                navigation: meetingsNavigation
            )
            // Pin structural identity so `destinationMain` branch
            // re-evaluations never tear down the screen's internal @State.
            .id(TodayNavSelection.meetings)
        } else {
            // The meetings stack failed to compose at launch (no store) —
            // nothing real to show.
            LiquidEmptyState(
                systemImage: "person.wave.2",
                message: "Meetings are unavailable in this session."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Right-inspector slot content for `.meetings` (Follow-ups / Send
    /// Summary / Insights / Next Meeting, 304 pt); `nil` everywhere else so
    /// the column disappears entirely.
    var meetingsInspectorSlot: (() -> AnyView)? {
        guard selection == .meetings, let meetingsComposition, let meetingNavigationRouter else {
            return nil
        }
        let model = liquidMeetingsModel
        let navigation = meetingsNavigation
        return {
            AnyView(
                MeetingActionsInspector(
                    model: model,
                    composition: meetingsComposition,
                    router: meetingNavigationRouter,
                    navigation: navigation
                )
            )
        }
    }

    /// Cross-module navigation seams for the knowledge column / inspector.
    /// Tasks route through `openTask` (inspector ⊥ Agent invariant preserved);
    /// projects select on the shared Projects model before navigating so the
    /// destination opens on the right project; notes/people/settings navigate
    /// to their shell destinations (no per-item deep-link seams exist there).
    private var meetingsNavigation: LiquidMeetingsNavigation {
        LiquidMeetingsNavigation(
            openTask: { openTask($0) },
            openNotes: { navigate(to: .notes) },
            openProject: { projectID in
                liquidProjectsModel.selectedProjectID = projectID
                navigate(to: .projects)
            },
            openPeople: { navigate(to: .people) },
            openSettings: { navigate(to: .settings) },
            // Re-homed from the deleted pre-Liquid MeetingDetailToolbar: drive the
            // helper's cross-process PipelineQueue cancel over XPC. `nil` when no
            // helper control is injected, which hides the Cancel affordance.
            cancelProcessing: meetingHelperControl.map { control in
                { meetingID in control.cancelProcessing(meetingID: meetingID) }
            }
        )
    }
}
