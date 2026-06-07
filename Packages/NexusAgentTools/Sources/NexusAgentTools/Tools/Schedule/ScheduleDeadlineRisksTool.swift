import Foundation
import NexusCore
import SwiftData

/// `schedule.deadlineRisks` (spec §19.1 / §12): forward-looking, read-only risk
/// projection for open tasks with a deadline inside the horizon. Pure signal — it
/// never schedules or moves anything. Suitable for a morning brief.
public struct ScheduleDeadlineRisksTool: AgentTool {
    public let name = "schedule.deadline_risks"
    public let description =
        "Projects deadline risk for open tasks with a deadline in the horizon: for "
        + "each, whether it is on-track, tight, or at-risk given competing higher- or "
        + "equal-priority work and the free time before the deadline. Read-only signal — "
        + "it never schedules anything."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "horizon_days": .integer(
                minimum: 1,
                maximum: 60,
                description: "How many days ahead to project (default 14)."
            )
        ],
        required: []
    )

    private let estimator: any DurationEstimator
    private let provider: any CalendarEventProviding
    private let preferencesStore: UserDefaultsCalendarPreferencesStore

    public init(
        provider: any CalendarEventProviding,
        estimator: any DurationEstimator = HeuristicDurationEstimator(),
        preferencesStore: UserDefaultsCalendarPreferencesStore = UserDefaultsCalendarPreferencesStore()
    ) {
        self.provider = provider
        self.estimator = estimator
        self.preferencesStore = preferencesStore
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let horizonDays = try TasksToolArguments.boundedInt(
            args["horizon_days"], field: "horizon_days", default: 14, range: 1...60
        )
        let now = context.now()
        let calendar = Calendar.current
        let horizon = TimeInterval(horizonDays * 24 * 60 * 60)
        let prefs = preferencesStore.load()

        let modelContext = context.modelContext.context
        let tasks = try ScheduleToolSupport.openTasks(context: modelContext)
        let history = try ScheduleToolSupport.history(context: modelContext)
        let events = await ScheduleToolSupport.events(
            provider: provider, start: now, end: now.addingTimeInterval(horizon)
        )

        let risks = DeadlineRiskAnalyzer().analyze(
            tasks: tasks,
            events: events,
            prefs: prefs,
            estimator: estimator,
            history: history,
            horizon: horizon,
            now: now,
            calendar: calendar
        )
        return try TasksToolJSON.encode(risks.map(DeadlineRiskDTO.init(from:)))
    }
}
