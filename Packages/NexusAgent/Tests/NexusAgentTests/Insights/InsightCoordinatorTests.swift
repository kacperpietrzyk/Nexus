import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@MainActor
@Suite struct InsightCoordinatorTests {
    // MARK: - Shared helpers

    private func makeAssembler() throws -> ContextAssembler {
        let schema = Schema([TaskItem.self, Project.self, Person.self, Note.self, Link.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none)
        let ctx = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let repo = TaskItemRepository(context: ctx, scheduler: RRuleScheduler(), now: { .now })
        let agentContext = AgentContext(
            modelContext: ModelContextRef(ctx),
            taskRepository: TaskItemRepositoryRef(repo),
            searchIndex: SearchIndex(),
            now: { .now })
        struct EmptyRetriever: RagRetriever {
            func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] { [] }
        }
        return ContextAssembler(agentContext: agentContext, retriever: EmptyRetriever())
    }

    private func makeDecomposeCoordinator(golden: String) throws -> MeetingDecomposeCoordinator {
        MeetingDecomposeCoordinator(
            runner: SkillRunner(
                inference: ScriptedSkillInference(responses: [golden]),
                assembler: try makeAssembler()),
            scheduler: SlotScheduler(),
            workload: WorkloadAnalyzer(),
            capacity: CapacityModel(dailyCapacityMinutes: 480),
            prefs: .default,
            events: [],
            now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// An overloaded task for a given `now` date (700 min vs 240 min capacity).
    private func overloadedTask(now: Date) -> ScheduledItem {
        ScheduledItem(id: UUID(), durationMinutes: 700, day: now)
    }

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - Overload cooldown

    @Test func overloadFiresOnceAndRespects6hCooldown() async throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)

        let defaults = UserDefaults(suiteName: "ic-overload-\(UUID().uuidString)")!
        let cooldown = InsightCooldownStore(defaults: defaults, now: { clock })
        let pending = PendingInsightStore()
        let calendar = utcCalendar
        let assembler = try makeAssembler()

        let coordinator = InsightCoordinator(
            cooldown: cooldown,
            pending: pending,
            tasks: { [self] in [overloadedTask(now: clock)] },
            events: { [] },
            capacity: { CapacityModel(dailyCapacityMinutes: 240) },
            meetingsNeedingDecompose: { [] },
            dayPlanRunner: nil,
            dayPlanNumbers: { "0 tasks" },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: SkillRunner(
                        inference: ScriptedSkillInference(responses: []),
                        assembler: assembler),
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: CapacityModel(dailyCapacityMinutes: 480),
                    prefs: .default,
                    events: [],
                    now: clock)
            },
            now: { clock },
            calendar: calendar)

        // First call — should add one overload entry.
        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)
        #expect(pending.pending.first?.kind == "overload")

        // Second immediate call — cooldown blocks it.
        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)

        // Simulate dismiss + advance clock past 6h.
        let entryID = pending.pending[0].id
        pending.resolve(id: entryID)
        clock = clock.addingTimeInterval(6 * 3_600 + 1)

        // Re-fire after cooldown.
        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)
    }

    // MARK: - Day plan cooldown (12h per-day bucket)

    @Test func dayPlanFiresOncePerDayBucket() async throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let ordering = "Start with the contract review, then tackle emails."

        let defaults = UserDefaults(suiteName: "ic-dayplan-\(UUID().uuidString)")!
        let cooldown = InsightCooldownStore(defaults: defaults, now: { clock })
        let pending = PendingInsightStore()

        let runner = SkillRunner(
            inference: ScriptedSkillInference(responses: [ordering, ordering, ordering]),
            assembler: try makeAssembler())
        let assembler = try makeAssembler()

        let coordinator = InsightCoordinator(
            cooldown: cooldown,
            pending: pending,
            tasks: { [] },
            events: { [] },
            capacity: { CapacityModel(dailyCapacityMinutes: 480) },
            meetingsNeedingDecompose: { [] },
            dayPlanRunner: runner,
            dayPlanNumbers: { "2 tasks due" },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: SkillRunner(
                        inference: ScriptedSkillInference(responses: []),
                        assembler: assembler),
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: CapacityModel(dailyCapacityMinutes: 480),
                    prefs: .default,
                    events: [],
                    now: clock)
            },
            now: { clock },
            calendar: .current)

        // First call — should add one day_plan entry.
        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)
        #expect(pending.pending.first?.kind == "day_plan")

        // Same-day second call — same bucket key, cooldown blocks.
        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)
    }

    // MARK: - Meeting decompose

    @Test func meetingDecomposeFiresForEmptyActionItemIDs() async throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let golden = #"{"tasks":[{"title":"Draft contract","estMinutes":60}]}"#
        let meetingID = UUID()

        let defaults = UserDefaults(suiteName: "ic-decompose-\(UUID().uuidString)")!
        let cooldown = InsightCooldownStore(defaults: defaults, now: { clock })
        let pending = PendingInsightStore()
        let assembler = try makeAssembler()

        let coordinator = InsightCoordinator(
            cooldown: cooldown,
            pending: pending,
            tasks: { [] },
            events: { [] },
            capacity: { CapacityModel(dailyCapacityMinutes: 480) },
            meetingsNeedingDecompose: {
                [
                    MeetingDecomposeCandidate(
                        id: meetingID,
                        summary: "We agreed to draft the contract.",
                        actionItemIDs: [])
                ]
            },
            dayPlanRunner: nil,
            dayPlanNumbers: { "0 tasks" },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: SkillRunner(
                        inference: ScriptedSkillInference(responses: [golden]),
                        assembler: assembler),
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: CapacityModel(dailyCapacityMinutes: 480),
                    prefs: .default,
                    events: [],
                    now: clock)
            },
            now: { clock },
            calendar: .current)

        await coordinator.runDueInsights(now: clock)
        #expect(pending.pending.count == 1)
        #expect(pending.pending.first?.kind == "meeting_decompose")
    }

    @Test func meetingDecomposeSkippedWhenPipelineCreatedTasks() async throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let meetingID = UUID()

        let defaults = UserDefaults(suiteName: "ic-decompose-skip-\(UUID().uuidString)")!
        let cooldown = InsightCooldownStore(defaults: defaults, now: { clock })
        let pending = PendingInsightStore()
        let assembler = try makeAssembler()

        let coordinator = InsightCoordinator(
            cooldown: cooldown,
            pending: pending,
            tasks: { [] },
            events: { [] },
            capacity: { CapacityModel(dailyCapacityMinutes: 480) },
            meetingsNeedingDecompose: {
                [
                    MeetingDecomposeCandidate(
                        id: meetingID,
                        summary: "Discussed roadmap.",
                        actionItemIDs: [UUID()])
                ]
            },
            dayPlanRunner: nil,
            dayPlanNumbers: { "0 tasks" },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: SkillRunner(
                        inference: ScriptedSkillInference(responses: []),
                        assembler: assembler),
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: CapacityModel(dailyCapacityMinutes: 480),
                    prefs: .default,
                    events: [],
                    now: clock)
            },
            now: { clock },
            calendar: .current)

        await coordinator.runDueInsights(now: clock)
        // Non-empty actionItemIDs: proposalIfEligible returns nil → nothing added.
        #expect(pending.pending.isEmpty)
    }

    // MARK: - Failure isolation

    @Test func dayPlanFailureDoesNotBlockMeetingDecompose() async throws {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let golden = #"{"tasks":[{"title":"Follow-up email","estMinutes":30}]}"#
        let meetingID = UUID()

        let defaults = UserDefaults(suiteName: "ic-isolation-\(UUID().uuidString)")!
        let cooldown = InsightCooldownStore(defaults: defaults, now: { clock })
        let pending = PendingInsightStore()
        let assembler = try makeAssembler()

        // Feeding [""] causes DayPlanInsight to fail on decode (empty plan),
        // then retry also returns "" → throws SkillRunError.invalidOutputAfterRetry.
        let failingRunner = SkillRunner(
            inference: ScriptedSkillInference(responses: [""]),
            assembler: try makeAssembler())

        let coordinator = InsightCoordinator(
            cooldown: cooldown,
            pending: pending,
            tasks: { [] },
            events: { [] },
            capacity: { CapacityModel(dailyCapacityMinutes: 480) },
            meetingsNeedingDecompose: {
                [
                    MeetingDecomposeCandidate(
                        id: meetingID,
                        summary: "We agreed to draft the contract.",
                        actionItemIDs: [])
                ]
            },
            dayPlanRunner: failingRunner,
            dayPlanNumbers: { "1 task" },
            makeDecomposeCoordinator: {
                MeetingDecomposeCoordinator(
                    runner: SkillRunner(
                        inference: ScriptedSkillInference(responses: [golden]),
                        assembler: assembler),
                    scheduler: SlotScheduler(),
                    workload: WorkloadAnalyzer(),
                    capacity: CapacityModel(dailyCapacityMinutes: 480),
                    prefs: .default,
                    events: [],
                    now: clock)
            },
            now: { clock },
            calendar: .current)

        await coordinator.runDueInsights(now: clock)
        // day_plan failed, but meeting_decompose (#3) should still have fired.
        let kinds = pending.pending.map(\.kind)
        #expect(kinds.contains("meeting_decompose"))
    }
}
