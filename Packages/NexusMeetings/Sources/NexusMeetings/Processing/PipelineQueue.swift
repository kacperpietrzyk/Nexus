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

    /// Watchdog ceiling for a single job. A hung ML stage (an MLX.eval / ASR
    /// inference that never returns and does not observe `Task` cancellation)
    /// would otherwise wedge `await task.value` forever and block EVERY later
    /// meeting behind it. When a job exceeds this, the queue cancels it and stops
    /// awaiting it so processing can proceed. Generous enough that a legitimately
    /// long meeting never trips it.
    private let jobTimeout: Duration

    /// Per-process engine reset run when the watchdog abandons a hung job. The
    /// abandoned job keeps running (MLX/ASR inference ignores cooperative
    /// cancellation) as a zombie contending for GPU/ANE; cancelling it is not
    /// enough. `recover` drops the wedged on-device engine(s) resident in THIS
    /// process and swaps in fresh ones so resources release and the queue can
    /// make progress. `nil` when the process feeds no ML jobs (e.g. iOS). It runs
    /// BEFORE the drain resumes, so the next job never starts on a wedged engine.
    private let recover: (@Sendable () async -> Void)?

    /// Resumes the drain loop for the current job exactly once — whichever of the
    /// job's completion or the watchdog timeout happens first. Actor-isolated, so
    /// the two racing tasks resolve it without a data race.
    private var drainContinuation: CheckedContinuation<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    /// Monotonic id for the current job cycle. A job abandoned on timeout keeps
    /// running (MLX ignores cancellation) and can complete much later — its stale
    /// completion callback must not touch the NEXT job's watchdog/continuation.
    /// Every callback is stamped with the epoch it was armed under and ignored if
    /// the cycle has since moved on.
    private var jobEpoch: UInt64 = 0

    public init(
        jobTimeout: Duration = .seconds(900),
        recover: (@Sendable () async -> Void)? = nil
    ) {
        self.jobTimeout = jobTimeout
        self.recover = recover
    }

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
            await awaitJobOrTimeout(task)
            runningTask = nil
            runningMeetingID = nil
        }
        running = false
    }

    /// Awaits the running job, but no longer than `jobTimeout`. On timeout the job
    /// is cancelled (cooperative — a stage-boundary check will throw) and the drain
    /// loop is released WITHOUT waiting for the job to actually unwind, so a hung
    /// stage can never block subsequent meetings. The abandoned job task is left to
    /// finish on its own; its late completion is a no-op (the continuation is
    /// already resumed).
    private func awaitJobOrTimeout(_ job: Task<Void, Never>) async {
        jobEpoch &+= 1
        let epoch = jobEpoch
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            drainContinuation = continuation
            watchdogTask = Task { [weak self, jobTimeout] in
                try? await Task.sleep(for: jobTimeout)
                // On normal completion the watchdog is cancelled; `try?` swallows the
                // sleep's CancellationError, so guard here or we would spuriously
                // cancel the NEXT job that has since started running.
                guard !Task.isCancelled else { return }
                await self?.handleWatchdogTimeout(epoch: epoch)
            }
            Task { [weak self] in
                await job.value
                await self?.handleJobCompletion(epoch: epoch)
            }
        }
    }

    private func handleJobCompletion(epoch: UInt64) {
        // Ignore a late completion from a job already abandoned on timeout — it must
        // not cancel the current job's watchdog or resume its continuation.
        guard epoch == jobEpoch else { return }
        watchdogTask?.cancel()
        watchdogTask = nil
        resumeDrain()
    }

    private func handleWatchdogTimeout(epoch: UInt64) async {
        guard epoch == jobEpoch else { return }
        NSLog(
            "Nexus meetings: pipeline job timed out after %llds; abandoning it to unblock the queue",
            jobTimeout.components.seconds
        )
        runningTask?.cancel()
        // Reset the on-device engine(s) BEFORE resuming the drain: the abandoned
        // job is a non-cancellable zombie still holding the GPU/ANE, so the next
        // job would otherwise start on a wedged engine. `recover` must finish
        // before `resumeDrain` releases the loop to the next job.
        if let recover {
            await recover()
        }
        resumeDrain()
    }

    private func resumeDrain() {
        guard let continuation = drainContinuation else { return }
        drainContinuation = nil
        continuation.resume()
    }
}
