import Foundation
import NexusCore
import SwiftData

/// `schedule.planDay` (spec §6 / §19.2 / §12): generate proposed blocks for the
/// open worklist over a horizon and PERSIST them as live `proposed` / `auto`
/// blocks (so `schedule.acceptBlock` / `schedule.rejectBlock` have block ids to
/// act on). A re-run is idempotent in spirit: existing `proposed` blocks in the
/// horizon are cleared first, then fresh proposals are persisted. Accepted blocks
/// are never touched (anti-thrash, spec §6).
public struct SchedulePlanDayTool: AgentTool {
    public let name = "schedule.plan_day"
    public let description =
        "Plans the day: generates proposed time blocks for the open worklist "
        + "(overdue + due-today + pinned) in the free gaps around calendar events and "
        + "already-accepted blocks, and persists them as proposed blocks. "
        + "Re-running replaces existing proposed blocks in the horizon; accepted blocks "
        + "are never moved. Returns the proposals plus an overload report."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "horizon_days": .integer(
                minimum: 1,
                maximum: 14,
                description: "Number of working days to plan across (default 1 = today only)."
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
            args["horizon_days"], field: "horizon_days", default: 1, range: 1...14
        )
        let now = context.now()
        let calendar = Calendar.current
        let prefs = preferencesStore.load()

        // Horizon window: from now through the end of the last working day.
        let windowStart = calendar.startOfDay(for: now)
        let lastDay = calendar.date(byAdding: .day, value: horizonDays, to: windowStart) ?? now
        let windowEnd = calendar.startOfDay(for: lastDay)

        let modelContext = context.modelContext.context
        let blocks = ScheduledBlockRepository(context: modelContext, now: context.now)

        let candidates = try ScheduleToolSupport.candidates(context: modelContext, now: now)
        let history = try ScheduleToolSupport.history(context: modelContext)
        let accepted = try ScheduleToolSupport.acceptedBlocks(
            repository: blocks, start: windowStart, end: windowEnd
        )
        let events = await ScheduleToolSupport.events(
            provider: provider, start: windowStart, end: windowEnd
        )

        // Clear stale proposed blocks in the horizon so a re-plan never stacks
        // duplicates (anti-thrash dedup; accepted blocks above are untouched).
        try clearProposedBlocks(repository: blocks, start: windowStart, end: windowEnd)

        let plan = DayScheduler().plan(
            candidates: candidates,
            events: events,
            accepted: accepted,
            prefs: prefs,
            estimator: estimator,
            history: history,
            now: now,
            calendar: calendar,
            horizonDays: horizonDays
        )

        var dtos: [ScheduledBlockDTO] = []
        for proposal in plan.proposals {
            let block = try blocks.persistProposal(proposal)
            dtos.append(ScheduledBlockDTO(from: block))
        }

        let response = PlanDayResponseDTO(
            proposals: dtos,
            overload: OverloadReportDTO(from: plan.overload)
        )
        return try TasksToolJSON.encode(response)
    }

    @MainActor
    private func clearProposedBlocks(
        repository: ScheduledBlockRepository,
        start: Date,
        end: Date
    ) throws {
        let proposedRaw = ScheduledBlockStatus.proposed.rawValue
        let stale = try repository.blocks(from: start, to: end).filter { $0.statusRaw == proposedRaw }
        for block in stale {
            try repository.softDelete(block)
        }
    }
}
