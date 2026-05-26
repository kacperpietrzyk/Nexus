import Foundation
import Testing

@testable import NexusCore

@Test func systemJobClock_now_returnsCurrentDate() {
    let clock = SystemJobClock()
    let before = Date.now
    let now = clock.now()
    let after = Date.now
    #expect(now >= before)
    #expect(now <= after)
}

@Test func fakeJobClock_advance_movesNowForward() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let clock = FakeJobClock(start: start)
    #expect(clock.now() == start)
    clock.advance(by: 60)
    #expect(clock.now() == start.addingTimeInterval(60))
}

@Test func scheduler_register_storesJob() async {
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock)
    let job = ScheduledJob(
        id: .tombstonePurge,
        interval: 86_400,
        run: { _ in }
    )
    await scheduler.register(job)
    let ids = await scheduler.registeredJobIDs()
    #expect(ids == [.tombstonePurge])
}

@Test func scheduler_runDue_executesJobWhenIntervalElapsed() async {
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock)
    let counter = Counter()
    let job = ScheduledJob(
        id: .tombstonePurge,
        interval: 60,
        run: { _ in await counter.increment() }
    )
    await scheduler.register(job)

    await scheduler.runDue()
    #expect(await counter.value == 1)

    await scheduler.runDue()
    #expect(await counter.value == 1)

    clock.advance(by: 30)
    await scheduler.runDue()
    #expect(await counter.value == 1)

    clock.advance(by: 30)
    await scheduler.runDue()
    #expect(await counter.value == 2)
}

@Test func scheduler_runDue_runsAllDueJobs() async {
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock)
    let a = Counter()
    let b = Counter()
    await scheduler.register(ScheduledJob(id: .tombstonePurge, interval: 10, run: { _ in await a.increment() }))
    await scheduler.register(ScheduledJob(id: .indexBuilder, interval: 10, run: { _ in await b.increment() }))

    await scheduler.runDue()
    #expect(await a.value == 1)
    #expect(await b.value == 1)
}

@Test func scheduler_runDue_swallowsErrors() async {
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock)
    let counter = Counter()
    await scheduler.register(
        ScheduledJob(
            id: .tombstonePurge,
            interval: 10,
            run: { _ in
                await counter.increment()
                throw TestError.boom
            }
        )
    )
    await scheduler.runDue()
    #expect(await counter.value == 1)

    await scheduler.runDue()
    #expect(await counter.value == 1)
}

private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}

private enum TestError: Error { case boom }
