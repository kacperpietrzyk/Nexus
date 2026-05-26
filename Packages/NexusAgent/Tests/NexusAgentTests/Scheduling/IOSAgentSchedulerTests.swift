import Foundation
import NexusUI
import Testing

@testable import NexusAgent

@MainActor
@Test func iosSchedulerCatchesUpForegroundForMissedFires() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = Date.now.addingTimeInterval(-24 * 3600)
    }
    var fired = false
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fired = true },
        bgScheduler: FakeBGTaskScheduler()
    )
    await scheduler.foregroundCatchUp()
    #expect(fired)
}

@MainActor
@Test func iosSchedulerSubmitsBGRequest() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    _ = try scheduleStore.create(
        name: "Hourly",
        cronExpression: "0 * * * *",
        prompt: "ping"
    )
    let fake = FakeBGTaskScheduler()
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in },
        bgScheduler: fake
    )
    await scheduler.start()
    #expect(fake.submittedIdentifiers.contains("nexus.agent.scheduleRun"))
}

@MainActor
@Test func iosSchedulerStartSubmitsInitialBGRequestOnce() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    _ = try scheduleStore.create(
        name: "Hourly",
        cronExpression: "0 * * * *",
        prompt: "ping"
    )
    let fake = FakeBGTaskScheduler()
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in },
        bgScheduler: fake
    )

    await scheduler.start()
    await scheduler.start()

    #expect(fake.submittedIdentifiers == ["nexus.agent.scheduleRun"])
}

@MainActor
@Test func iosSchedulerBackgroundDeliveryResubmitsBGRequestAfterStart() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    _ = try scheduleStore.create(
        name: "Hourly",
        cronExpression: "0 * * * *",
        prompt: "ping"
    )
    let fake = FakeBGTaskScheduler()
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in },
        bgScheduler: fake
    )

    await scheduler.start()
    await scheduler.runBackgroundTask()

    let expectedIdentifiers = [
        "nexus.agent.scheduleRun",
        "nexus.agent.scheduleRun",
    ]
    #expect(fake.submittedIdentifiers == expectedIdentifiers)
}

@MainActor
@Test func iosSchedulerCatchUpRetriesWhenFireDoesNotAdvanceLastRun() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = Date.now.addingTimeInterval(-24 * 3600)
    }
    var fireCount = 0
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fireCount += 1 },
        bgScheduler: FakeBGTaskScheduler()
    )

    await scheduler.foregroundCatchUp()
    await scheduler.foregroundCatchUp()

    #expect(fireCount == 2)
}

@MainActor
@Test func iosSchedulerCatchUpDoesNotRepeatAfterLastRunAdvances() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    let now = Date.now
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = now.addingTimeInterval(-24 * 3600)
    }
    var fireCount = 0
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { scheduleID in
            fireCount += 1
            if let schedule = try? scheduleStore.get(id: scheduleID) {
                schedule.lastRunAt = now
            }
        },
        bgScheduler: FakeBGTaskScheduler()
    )

    await scheduler.foregroundCatchUp(now: now)
    await scheduler.foregroundCatchUp(now: now)

    #expect(fireCount == 1)
}

@MainActor
@Test func iosSchedulerCatchUpSkipsSameDueSlotWhileInFlight() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    let now = Date.now
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = now.addingTimeInterval(-24 * 3600)
    }
    var fireCount = 0
    var didEnterFirstFire = false
    var nestedCatchUp: Task<Void, Never>?
    var releaseFirstFire: CheckedContinuation<Void, Never>?
    var scheduler: IOSAgentScheduler!
    scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { scheduleID in
            fireCount += 1
            guard fireCount == 1 else { return }

            didEnterFirstFire = true
            nestedCatchUp = Task { @MainActor in
                await scheduler.foregroundCatchUp(now: now)
            }
            await withCheckedContinuation { continuation in
                releaseFirstFire = continuation
            }
            if let schedule = try? scheduleStore.get(id: scheduleID) {
                schedule.lastRunAt = now
            }
        },
        bgScheduler: FakeBGTaskScheduler()
    )

    let firstCatchUp = Task { @MainActor in
        await scheduler.foregroundCatchUp(now: now)
    }
    while !didEnterFirstFire {
        await Task.yield()
    }
    await nestedCatchUp?.value
    releaseFirstFire?.resume()
    await firstCatchUp.value

    #expect(fireCount == 1)
}

@MainActor
@Test func iosSchedulerCatchUpDoesNotFireWhenTaskIsCancelled() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = Date.now.addingTimeInterval(-24 * 3600)
    }
    var fireCount = 0
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fireCount += 1 },
        bgScheduler: FakeBGTaskScheduler()
    )

    let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await scheduler.foregroundCatchUp()
    }
    await task.value

    #expect(fireCount == 0)
}

@MainActor
@Test func bgTaskCompletionGuardCompletesOnlyOnce() {
    let completion = BGTaskCompletionGuard()
    var statuses: [Bool] = []

    #expect(completion.complete(success: false) { statuses.append($0) })
    #expect(!completion.complete(success: true) { statuses.append($0) })

    #expect(statuses == [false])
}

@MainActor
@Test func iosSchedulerVacationModeSkipsFireAndMarksSchedule() async throws {
    let ctx = try AgentTestSupport.makeContext()
    let scheduleStore = AgentScheduleStore(context: ctx)
    let id = try scheduleStore.create(
        name: "Morning Brief",
        cronExpression: "0 8 * * *",
        prompt: "ping"
    )
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    if let schedule = try scheduleStore.get(id: id) {
        schedule.lastRunAt = now.addingTimeInterval(-24 * 3600)
    }
    let suite = "test-vac-ios-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: NexusPreferences.Keys.agentVacationMode)
    var fired = false
    let scheduler = IOSAgentScheduler(
        scheduleStore: scheduleStore,
        onFire: { _ in fired = true },
        vacationModeGate: VacationModeGate(defaults: defaults),
        bgScheduler: FakeBGTaskScheduler()
    )

    await scheduler.foregroundCatchUp(now: now)

    let updated = try #require(try scheduleStore.get(id: id))
    #expect(!fired)
    #expect(updated.lastRunAt == now)
    #expect(updated.lastRunStatus == .skipped)
    #expect(updated.lastRunResultRef == nil)
}

@MainActor
private final class FakeBGTaskScheduler: BGTaskSchedulerInterface {
    var submittedIdentifiers: [String] = []

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        submittedIdentifiers.append(identifier)
    }
}
