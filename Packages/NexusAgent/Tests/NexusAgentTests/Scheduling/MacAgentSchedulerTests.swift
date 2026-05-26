import Foundation
import NexusUI
import Testing

@testable import NexusAgent

@MainActor
@Test func macSchedulerFiresAtNextCronInstant() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Every minute",
        cronExpression: "* * * * *",
        prompt: "ping"
    )
    var firedID: UUID?
    let scheduler = MacAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { firedID = $0 },
        tickInterval: .milliseconds(50),
        shouldInstallLoginItem: false
    )
    await scheduler.start()
    try await Task.sleep(for: .milliseconds(150))
    await scheduler.suspendAll()
    #expect(firedID == id)
}

@MainActor
@Test func macSchedulerSkipsDisabledSchedules() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    _ = try scheduleStore.create(
        name: "Disabled",
        cronExpression: "* * * * *",
        prompt: "ping",
        enabled: false
    )
    var fired = false
    let scheduler = MacAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fired = true },
        tickInterval: .milliseconds(50),
        shouldInstallLoginItem: false
    )
    await scheduler.start()
    try await Task.sleep(for: .milliseconds(150))
    await scheduler.suspendAll()
    #expect(!fired)
}

@MainActor
@Test func macSchedulerFiresOnlyOncePerCronMinute() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Every minute",
        cronExpression: "* * * * *",
        prompt: "ping"
    )
    var firedIDs: [UUID] = []
    let scheduler = MacAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { firedIDs.append($0) },
        shouldInstallLoginItem: false
    )
    let firstTick = Date(timeIntervalSince1970: 1_800_000_000)
    let secondTickSameMinute = firstTick.addingTimeInterval(30)

    await scheduler.tickForTesting(now: firstTick)
    await scheduler.tickForTesting(now: secondTickSameMinute)

    #expect(firedIDs == [id])
}

@MainActor
@Test func macSchedulerVacationModeSkipsFireAndMarksSchedule() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Every minute",
        cronExpression: "* * * * *",
        prompt: "ping"
    )
    let suite = "test-vac-mac-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: NexusPreferences.Keys.agentVacationMode)
    var fired = false
    let scheduler = MacAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fired = true },
        vacationModeGate: VacationModeGate(defaults: defaults),
        shouldInstallLoginItem: false
    )
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    await scheduler.tickForTesting(now: now)

    let updated = try #require(try scheduleStore.get(id: id))
    #expect(!fired)
    #expect(updated.lastRunAt == now)
    #expect(updated.lastRunStatus == .skipped)
    #expect(updated.lastRunResultRef == nil)
}
