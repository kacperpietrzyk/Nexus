import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("Schedule agent tools")
struct ScheduleToolsTests {
    // A fixed "now" inside a weekday working window (2023-11-14 is a Tuesday).
    // 09:00 UTC sits at the start of the default 09:00–18:00 window in UTC.
    private static let fixedNow = Date(timeIntervalSince1970: 1_700_038_800)  // 2023-11-15 09:00:00 UTC
    private static func now() -> Date { fixedNow }

    private func utcPreferencesStore() -> UserDefaultsCalendarPreferencesStore {
        // Isolated, empty defaults so the default 09:00–18:00 window applies and
        // no stray writeCalendarID leaks across tests.
        let defaults = UserDefaults(suiteName: "schedule-tools-\(UUID().uuidString)")!
        return UserDefaultsCalendarPreferencesStore(defaults: defaults)
    }

    // MARK: - tasks.estimateDuration

    @MainActor
    @Test("tasks.estimateDuration returns explicit estimate without persisting")
    func estimateDurationExplicit() async throws {
        let task = TaskItem(
            title: "write report",
            estimatedDurationSeconds: 3600,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)

        let result = try await TasksEstimateDurationTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(DurationEstimateDTO.self, from: result)
        #expect(dto.seconds == 3600)
        #expect(dto.confidence == 1.0)
        #expect(dto.taskID == task.id.uuidString)
    }

    @MainActor
    @Test("tasks.estimateDuration on unknown task throws notFound")
    func estimateDurationNotFound() async throws {
        let fixture = try await InMemoryAgentContext.make(now: Self.now)
        await #expect(throws: AgentError.self) {
            _ = try await TasksEstimateDurationTool().call(
                args: .object(["task_id": .string(UUID().uuidString)]),
                context: fixture.context
            )
        }
    }

    // MARK: - schedule.planDay

    @MainActor
    @Test("schedule.planDay persists proposed blocks for due-today candidate")
    func planDayPersistsProposals() async throws {
        let due = Self.fixedNow  // due today
        let task = TaskItem(
            title: "ship feature",
            dueAt: due,
            estimatedDurationSeconds: 1800,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let provider = FakeCalendarProvider(stubEvents: [])

        let tool = SchedulePlanDayTool(provider: provider, preferencesStore: utcPreferencesStore())
        let result = try await tool.call(args: .object([:]), context: fixture.context)
        let response = try TasksToolJSON.decode(PlanDayResponseDTO.self, from: result)

        #expect(response.proposals.count == 1)
        #expect(response.proposals[0].taskID == task.id.uuidString)
        #expect(response.proposals[0].status == ScheduledBlockStatus.proposed.rawValue)
        #expect(response.proposals[0].externalEventID == nil)

        // Block is actually persisted.
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context)
        let persisted = try blocks.blocks(for: task.id)
        #expect(persisted.count == 1)
    }

    @MainActor
    @Test("schedule.planDay re-run replaces proposed blocks (no duplicate stacking)")
    func planDayIdempotentReplacesProposals() async throws {
        let task = TaskItem(
            title: "recurring plan",
            dueAt: Self.fixedNow,
            estimatedDurationSeconds: 1800,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let provider = FakeCalendarProvider()
        let tool = SchedulePlanDayTool(provider: provider, preferencesStore: utcPreferencesStore())

        _ = try await tool.call(args: .object([:]), context: fixture.context)
        _ = try await tool.call(args: .object([:]), context: fixture.context)

        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context)
        let live = try blocks.blocks(for: task.id)
        #expect(live.count == 1)  // not 2 — the first proposed block was cleared
    }

    @MainActor
    @Test("schedule.planDay leaves accepted blocks untouched on re-plan")
    func planDayDoesNotTouchAccepted() async throws {
        let task = TaskItem(
            title: "already accepted",
            dueAt: Self.fixedNow,
            estimatedDurationSeconds: 1800,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context, now: Self.now)
        let accepted = try blocks.create(
            taskID: task.id,
            start: Self.fixedNow.addingTimeInterval(3600),
            end: Self.fixedNow.addingTimeInterval(5400),
            status: .accepted,
            externalEventID: "evt-existing"
        )

        let provider = FakeCalendarProvider()
        let tool = SchedulePlanDayTool(provider: provider, preferencesStore: utcPreferencesStore())
        _ = try await tool.call(args: .object([:]), context: fixture.context)

        let still = try blocks.find(accepted.id)
        #expect(still != nil)
        #expect(still?.status == .accepted)
    }

    // MARK: - schedule.acceptBlock / rejectBlock

    @MainActor
    @Test("schedule.acceptBlock materializes a mirror event and marks accepted")
    func acceptBlockMaterializesEvent() async throws {
        let task = TaskItem(title: "accept me")
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context, now: Self.now)
        let block = try blocks.create(
            taskID: task.id,
            start: Self.fixedNow,
            end: Self.fixedNow.addingTimeInterval(1800),
            title: task.title
        )
        let provider = FakeCalendarProvider()

        let result = try await ScheduleAcceptBlockTool(writer: provider).call(
            args: .object(["block_id": .string(block.id.uuidString)]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(ScheduledBlockDTO.self, from: result)
        #expect(dto.status == ScheduledBlockStatus.accepted.rawValue)
        #expect(dto.externalEventID != nil)
        #expect(provider.createdDrafts.count == 1)
        #expect(provider.createdDrafts[0].calendarID == "nexus-cal")
    }

    @MainActor
    @Test("schedule.rejectBlock soft-deletes a proposed block")
    func rejectBlockSoftDeletes() async throws {
        let task = TaskItem(title: "reject me")
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context, now: Self.now)
        let block = try blocks.create(
            taskID: task.id,
            start: Self.fixedNow,
            end: Self.fixedNow.addingTimeInterval(1800)
        )
        let provider = FakeCalendarProvider()

        _ = try await ScheduleRejectBlockTool(writer: provider).call(
            args: .object(["block_id": .string(block.id.uuidString)]),
            context: fixture.context
        )
        #expect(try blocks.find(block.id) == nil)  // soft-deleted, no longer live
        #expect(provider.deletedIDs.isEmpty)  // proposed block had no mirror event
    }

    @MainActor
    @Test("schedule.rejectBlock deletes the mirror event of an accepted block")
    func rejectAcceptedDeletesEvent() async throws {
        let task = TaskItem(title: "accepted reject")
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context, now: Self.now)
        let block = try blocks.create(
            taskID: task.id,
            start: Self.fixedNow,
            end: Self.fixedNow.addingTimeInterval(1800),
            status: .accepted,
            externalEventID: "evt-99"
        )
        let provider = FakeCalendarProvider()

        _ = try await ScheduleRejectBlockTool(writer: provider).call(
            args: .object(["block_id": .string(block.id.uuidString)]),
            context: fixture.context
        )
        #expect(provider.deletedIDs == ["evt-99"])
        #expect(try blocks.find(block.id) == nil)
    }

    @MainActor
    @Test("schedule.rejectBlock surfaces a mirror-event delete failure instead of orphaning it (A3)")
    func rejectAcceptedSurfacesDeleteFailure() async throws {
        let task = TaskItem(title: "accepted reject")
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let blocks = ScheduledBlockRepository(context: fixture.context.modelContext.context, now: Self.now)
        let block = try blocks.create(
            taskID: task.id,
            start: Self.fixedNow,
            end: Self.fixedNow.addingTimeInterval(1800),
            status: .accepted,
            externalEventID: "evt-99"
        )
        let provider = FakeCalendarProvider()
        provider.deleteEventError = .accessDenied

        await #expect(throws: AgentError.self) {
            _ = try await ScheduleRejectBlockTool(writer: provider).call(
                args: .object(["block_id": .string(block.id.uuidString)]),
                context: fixture.context
            )
        }
        // The block must NOT be soft-deleted: rejecting it would orphan the mirror
        // event we couldn't delete.
        #expect(try blocks.find(block.id) != nil)
    }

    // MARK: - schedule.deadlineRisks

    @MainActor
    @Test("schedule.deadlineRisks flags an over-committed task as at-risk")
    func deadlineRisksAtRisk() async throws {
        // A task with a deadline 2 hours out but ~6h of estimated work → at risk.
        let deadline = Self.fixedNow.addingTimeInterval(2 * 3600)
        let task = TaskItem(
            title: "huge task",
            deadlineAt: deadline,
            estimatedDurationSeconds: 6 * 3600,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let provider = FakeCalendarProvider()

        let result = try await ScheduleDeadlineRisksTool(
            provider: provider, preferencesStore: utcPreferencesStore()
        ).call(args: .object([:]), context: fixture.context)
        let risks = try TasksToolJSON.decode([DeadlineRiskDTO].self, from: result)

        #expect(risks.count == 1)
        #expect(risks[0].taskID == task.id.uuidString)
        #expect(risks[0].severity == DeadlineRiskSeverity.atRisk.rawValue)
        #expect(risks[0].suggestedStartBy != nil)
    }

    @MainActor
    @Test("schedule.deadlineRisks ignores tasks without a deadline")
    func deadlineRisksNoDeadline() async throws {
        let task = TaskItem(title: "no deadline", dueAt: Self.fixedNow)
        let fixture = try await InMemoryAgentContext.make(tasks: [task], now: Self.now)
        let provider = FakeCalendarProvider()

        let result = try await ScheduleDeadlineRisksTool(
            provider: provider, preferencesStore: utcPreferencesStore()
        ).call(args: .object([:]), context: fixture.context)
        let risks = try TasksToolJSON.decode([DeadlineRiskDTO].self, from: result)
        #expect(risks.isEmpty)
    }
}
