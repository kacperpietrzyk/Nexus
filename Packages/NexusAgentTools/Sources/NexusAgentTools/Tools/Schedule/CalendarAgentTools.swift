import Foundation
import NexusCore

/// Convenience builder for the Calendar / Motion-AI agent tools (spec §12):
/// `tasks.estimateDuration`, `schedule.*`, and `calendar.events.*`.
///
/// These tools depend on the EventKit calendar provider, which is NOT part of the
/// shared `AgentContext` (only the schedule/calendar tools need it). So — exactly
/// like `MeetingsAgentTools.tools(meetingRepository:)` — the dependency is injected
/// at construction time by the composition root, and the tools are passed into the
/// agent registry as additional tools.
///
/// `provider` must conform to BOTH `CalendarEventProviding` (reads: events as
/// obstacles, `calendar.events.list`) and `CalendarEventWriting` (writes: accept,
/// event CRUD). `EventKitCalendarProvider` does. The estimator defaults to the
/// heuristic MVP (spec §5); MLX can later slot in behind the same protocol.
public enum CalendarAgentTools {
    public static func tools<Provider: CalendarEventProviding & CalendarEventWriting>(
        provider: Provider,
        estimator: any DurationEstimator = HeuristicDurationEstimator(),
        preferencesStore: UserDefaultsCalendarPreferencesStore = UserDefaultsCalendarPreferencesStore()
    ) -> [any AgentTool] {
        [
            TasksEstimateDurationTool(estimator: estimator),
            SchedulePlanDayTool(
                provider: provider, estimator: estimator, preferencesStore: preferencesStore
            ),
            ScheduleAcceptBlockTool(writer: provider),
            ScheduleRejectBlockTool(writer: provider),
            ScheduleDeadlineRisksTool(
                provider: provider, estimator: estimator, preferencesStore: preferencesStore
            ),
            CalendarEventsListTool(provider: provider),
            CalendarEventsCreateTool(writer: provider),
            CalendarEventsUpdateTool(writer: provider),
            CalendarEventsDeleteTool(writer: provider),
        ]
    }
}
