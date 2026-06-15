import Foundation

public actor PipelineQueue {
    public typealias Job = @MainActor () async -> Void

    private struct PendingJob {
        let meetingID: UUID?
        let job: Job
    }

    private var pending: [PendingJob] = []
    private var running = false
    private var runningMeetingID: UUID?
    private var runningTask: Task<Void, Never>?

    public init() {}

    public func enqueue(_ job: @escaping Job) {
        enqueue(meetingID: nil, job)
    }

    /// Enqueue a processing job tagged with the meeting it belongs to, so it can
    /// be cancelled by ``cancelProcessing(meetingID:)``. Untagged jobs (`nil`) are
    /// never cancellable.
    public func enqueue(meetingID: UUID?, _ job: @escaping Job) {
        pending.append(PendingJob(meetingID: meetingID, job: job))
        Task { await drainIfNeeded() }
    }

    /// Cancel processing for a meeting: drop any not-yet-started jobs queued for
    /// it, and signal cancellation to its job if it is the one currently running.
    ///
    /// Cancellation is cooperative — the running pipeline stops at the next stage
    /// boundary (each stage is preceded by `try Task.checkCancellation()`). It
    /// cannot interrupt a stage's in-flight ML inference (WhisperKit / Parakeet
    /// do not observe `Task` cancellation); that work finishes, then the next
    /// boundary check throws and the pipeline marks the stage failed.
    public func cancelProcessing(meetingID: UUID) {
        pending.removeAll { $0.meetingID == meetingID }
        if runningMeetingID == meetingID {
            runningTask?.cancel()
        }
    }

    public func waitUntilEmpty() async throws {
        while running || pending.isEmpty == false {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drainIfNeeded() async {
        guard running == false else { return }
        running = true
        while pending.isEmpty == false {
            let next = pending.removeFirst()
            runningMeetingID = next.meetingID
            let task = Task { @MainActor in
                await next.job()
            }
            runningTask = task
            await task.value
            runningTask = nil
            runningMeetingID = nil
        }
        running = false
    }
}
