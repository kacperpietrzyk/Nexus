import Foundation
import Testing

@testable import NexusMeetings

@Test func queueRunsJobsSerially() async throws {
    let queue = PipelineQueue()
    let counter = Counter()

    await queue.enqueue {
        await counter.increment()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    await queue.enqueue {
        await counter.increment()
    }

    try await queue.waitUntilEmpty()

    #expect(await counter.value == 2)
}

@Test func queueDoesNotOverlapRunningJobs() async throws {
    let queue = PipelineQueue()
    let recorder = QueueRunRecorder()

    await queue.enqueue {
        await recorder.start("first")
        try? await Task.sleep(nanoseconds: 10_000_000)
        await recorder.end("first")
    }
    await queue.enqueue {
        await recorder.start("second")
        await recorder.end("second")
    }

    try await queue.waitUntilEmpty()

    #expect(await recorder.maxConcurrent == 1)
    #expect(await recorder.events == ["start:first", "end:first", "start:second", "end:second"])
}

@Test func queueRunsJobEnqueuedWhileDraining() async throws {
    let queue = PipelineQueue()
    let recorder = QueueRunRecorder()

    await queue.enqueue {
        await recorder.start("first")
        await queue.enqueue {
            await recorder.start("second")
            await recorder.end("second")
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await recorder.end("first")
    }

    try await queue.waitUntilEmpty()

    #expect(await recorder.maxConcurrent == 1)
    #expect(await recorder.events == ["start:first", "end:first", "start:second", "end:second"])
}

@Test func queueCancelRemovesPendingJobForMeeting() async throws {
    let queue = PipelineQueue()
    let recorder = QueueRunRecorder()
    let blockerID = UUID()
    let cancelID = UUID()
    let release = Gate()

    // First job blocks the queue so the second stays pending and can be cancelled
    // before it ever runs.
    await queue.enqueue(meetingID: blockerID) {
        await recorder.start("blocker")
        await release.wait()
        await recorder.end("blocker")
    }
    await queue.enqueue(meetingID: cancelID) {
        await recorder.start("cancelled")
        await recorder.end("cancelled")
    }

    await queue.cancelProcessing(meetingID: cancelID)
    await release.open()
    try await queue.waitUntilEmpty()

    // The cancelled meeting's pending job never started.
    #expect(await recorder.events == ["start:blocker", "end:blocker"])
}

@Test func queueCancelSignalsRunningJobForMeeting() async throws {
    let queue = PipelineQueue()
    let observed = CancellationObserver()
    let runningID = UUID()
    let started = Gate()

    await queue.enqueue(meetingID: runningID) {
        await started.open()
        // Spin until the queue cancels this job's task.
        while Task.isCancelled == false {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        await observed.record(Task.isCancelled)
    }

    await started.wait()
    await queue.cancelProcessing(meetingID: runningID)
    try await queue.waitUntilEmpty()

    #expect(await observed.wasCancelled == true)
}

@Test func queueTimeoutAbandonsHungJobAndRunsNext() async throws {
    let queue = PipelineQueue(jobTimeout: .seconds(2))
    let recorder = QueueRunRecorder()
    let hang = Gate()

    await queue.enqueue {
        await recorder.start("hung")
        await hang.wait()  // never opened before the assertions → hangs past the timeout
        await recorder.end("hung")
    }
    await queue.enqueue {
        await recorder.start("next")
        await recorder.end("next")
    }

    // A hung ML stage (MLX.eval that ignores cancellation) must NOT wedge the whole
    // queue: the watchdog abandons it and the next meeting still processes.
    try await queue.waitUntilEmpty()

    let events = await recorder.events
    #expect(events.contains("start:next"))
    #expect(events.contains("end:next"))
    #expect(events.contains("end:hung") == false)  // abandoned, never finished

    await hang.open()  // release the abandoned job so it unwinds cleanly
}

@Test func queueTimeoutRunsRecoverOnceThenNextJob() async throws {
    let spy = RecoverSpy()
    let recorder = QueueRunRecorder()
    let queue = PipelineQueue(
        jobTimeout: .seconds(2),
        recover: {
            await spy.record()
            await recorder.mark("recover")
        }
    )
    let hang = Gate()

    await queue.enqueue {
        await recorder.start("hung")
        await hang.wait()  // never opened before the assertions → hangs past the timeout
        await recorder.end("hung")
    }
    await queue.enqueue {
        await recorder.start("next")
        await recorder.end("next")
    }

    // The watchdog abandons the hung job, then RESETS the on-device engine via
    // `recover` (so the zombie's GPU/ANE releases) BEFORE the drain resumes — and
    // the next meeting still processes on the fresh engine.
    try await queue.waitUntilEmpty()

    #expect(await spy.count == 1)  // fired once, only for the timed-out job
    let events = await recorder.events
    #expect(events.contains("start:next"))
    #expect(events.contains("end:next"))
    #expect(events.contains("end:hung") == false)  // abandoned, never finished
    // ORDERING IS CRITICAL: recover() must FINISH before the drain starts the next
    // job — otherwise the next job would run on the still-wedged engine. Awaited
    // before `resumeDrain`, so this is deterministic (no race).
    let recoverIndex = events.firstIndex(of: "recover")
    let nextStartIndex = events.firstIndex(of: "start:next")
    #expect(recoverIndex != nil)
    #expect(nextStartIndex != nil)
    if let recoverIndex, let nextStartIndex {
        #expect(recoverIndex < nextStartIndex)
    }

    await hang.open()  // release the abandoned job so it unwinds cleanly
}

@Test func queueLateCompletionOfAbandonedJobDoesNotDoubleRunNext() async throws {
    let queue = PipelineQueue(jobTimeout: .seconds(2))
    let recorder = QueueRunRecorder()
    let firstHang = Gate()
    let secondHang = Gate()

    await queue.enqueue {
        await recorder.start("first")
        await firstHang.wait()  // hang past the timeout → abandoned
        await recorder.end("first")
    }
    await queue.enqueue {
        await recorder.start("second")
        await secondHang.wait()  // stay running while the abandoned first completes late
        await recorder.end("second")
    }

    // Wait until the timeout abandoned `first` and `second` is running.
    while await recorder.events.contains("start:second") == false {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    // Late completion of the abandoned `first`: its stale callback must be ignored
    // (epoch guard) — it must not resume `second`'s wait or double-run anything.
    await firstHang.open()
    await secondHang.open()
    try await queue.waitUntilEmpty()

    let events = await recorder.events
    #expect(events.filter { $0 == "start:second" }.count == 1)
    #expect(events.filter { $0 == "end:second" }.count == 1)
    #expect(events.last == "end:second")
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor CancellationObserver {
    private(set) var wasCancelled = false

    func record(_ cancelled: Bool) {
        wasCancelled = cancelled
    }
}

private actor RecoverSpy {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor Counter {
    var value = 0

    func increment() {
        value += 1
    }
}

private actor QueueRunRecorder {
    private(set) var events: [String] = []
    private(set) var maxConcurrent = 0
    private var running = 0

    func mark(_ label: String) {
        events.append(label)
    }

    func start(_ id: String) {
        running += 1
        maxConcurrent = max(maxConcurrent, running)
        events.append("start:\(id)")
    }

    func end(_ id: String) {
        events.append("end:\(id)")
        running -= 1
    }
}
