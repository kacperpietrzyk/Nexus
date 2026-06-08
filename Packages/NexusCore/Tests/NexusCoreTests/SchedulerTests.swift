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

@Test func scheduler_retriesFailedJobBeforeFullInterval() async {
    // A failed job retries after the backoff (300s), well before its 1h interval (S5).
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock, retryBackoff: 300)
    let counter = Counter()
    await scheduler.register(
        ScheduledJob(
            id: .tombstonePurge,
            interval: 3600,
            run: { _ in
                await counter.increment()
                if await counter.value == 1 { throw TestError.boom }  // fail once, then succeed
            }
        )
    )

    await scheduler.runDue()  // attempt 1 → throws
    #expect(await counter.value == 1)

    // Before the backoff elapses it is NOT retried (no monopolising every tick).
    clock.advance(by: 60)
    await scheduler.runDue()
    #expect(await counter.value == 1)

    // After the backoff it retries — long before the 3600s interval — and succeeds.
    clock.advance(by: 300)
    await scheduler.runDue()  // attempt 2 → succeeds
    #expect(await counter.value == 2)

    // Having succeeded, it's back on the normal interval (no early re-run).
    clock.advance(by: 300)
    await scheduler.runDue()
    #expect(await counter.value == 2)
}

@Test func scheduler_retryBackoffDoublesAcrossConsecutiveFailures() async {
    // Pins the 2^(failures-1) escalation: backoff 300 → 600 → 1200 across three
    // consecutive failures, all below the 1h interval so the cap never masks it (S5).
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock, retryBackoff: 300)
    let counter = Counter()
    await scheduler.register(
        ScheduledJob(
            id: .tombstonePurge, interval: 3600,
            run: { _ in
                await counter.increment()
                throw TestError.boom  // always fails
            })
    )

    await scheduler.runDue()  // attempt 1 → fail (failures=1, next backoff 300)
    #expect(await counter.value == 1)

    // After failure 1: eligible at +300, not before.
    clock.advance(by: 299)
    await scheduler.runDue()
    #expect(await counter.value == 1)
    clock.advance(by: 1)
    await scheduler.runDue()  // attempt 2 → fail (failures=2, next backoff 600)
    #expect(await counter.value == 2)

    // After failure 2: backoff doubled to 600 — not eligible at +300.
    clock.advance(by: 300)
    await scheduler.runDue()
    #expect(await counter.value == 2)
    clock.advance(by: 300)  // total +600 since attempt 2
    await scheduler.runDue()  // attempt 3 → fail (failures=3, next backoff 1200)
    #expect(await counter.value == 3)

    // After failure 3: backoff doubled again to 1200 — not eligible at +600.
    clock.advance(by: 600)
    await scheduler.runDue()
    #expect(await counter.value == 3)
    clock.advance(by: 600)  // total +1200 since attempt 3
    await scheduler.runDue()  // attempt 4
    #expect(await counter.value == 4)
}

@Test func scheduler_perpetualFailureNeverRunsFasterThanInterval() async {
    // Anti-starvation preserved: backoff is capped at the job's interval, so an
    // always-failing short-interval job still runs at most once per interval (S5).
    let clock = FakeJobClock(start: Date(timeIntervalSince1970: 1_000_000))
    let scheduler = Scheduler(clock: clock, retryBackoff: 300)  // > interval below
    let counter = Counter()
    await scheduler.register(
        ScheduledJob(
            id: .tombstonePurge, interval: 100,
            run: { _ in
                await counter.increment()
                throw TestError.boom
            })
    )

    await scheduler.runDue()  // runs (count 1, fails)
    #expect(await counter.value == 1)

    clock.advance(by: 50)  // < interval
    await scheduler.runDue()
    #expect(await counter.value == 1)  // not yet

    clock.advance(by: 50)  // now a full interval elapsed
    await scheduler.runDue()
    #expect(await counter.value == 2)  // runs again, capped at interval, not the 300 backoff
}

private actor Counter {
    var value: Int = 0
    func increment() { value += 1 }
}

private enum TestError: Error { case boom }
