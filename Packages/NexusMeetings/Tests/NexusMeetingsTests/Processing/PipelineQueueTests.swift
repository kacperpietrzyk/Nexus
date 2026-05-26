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
