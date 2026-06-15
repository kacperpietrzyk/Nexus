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
