import Foundation

/// Stable identifier for scheduled jobs. Add cases as new modules add jobs (Phase 1+ extends with
/// `.indexBuilder`, `.dailyBriefing`, `.embeddingBackfill`, etc — Phase 0f only ships `.tombstonePurge`).
public enum JobID: String, Sendable, Hashable, CaseIterable {
    case tombstonePurge
    case indexBuilder  // reserved — used in 0d follow-up
    case dailyBriefing  // reserved — used in 0e/Phase 1
    case orderRebalance
    case dailyRollover  // Calendar/Motion-AI: roll unfinished due-today/overdue forward (spec §10)
}

/// One scheduled unit of work. `run` is `@Sendable` because the scheduler may invoke it from any
/// task context. `interval` is the minimum spacing between successful starts of two runs.
public struct ScheduledJob: Sendable {
    public let id: JobID
    public let interval: TimeInterval
    public let run: @Sendable (_ now: Date) async throws -> Void

    public init(
        id: JobID,
        interval: TimeInterval,
        run: @escaping @Sendable (_ now: Date) async throws -> Void
    ) {
        self.id = id
        self.interval = interval
        self.run = run
    }
}

/// Minimal in-process scheduler. Does NOT own an OS-level timer — callers (`Apps/Nexus*`) drive
/// `runDue()` via `BGTaskScheduler` (iOS) or `Timer` + lifecycle hooks (Mac). Phase 0f only schedules
/// `.tombstonePurge`; the multi-job declarative registry the spec mentions is deferred until a
/// second caller exists.
public actor Scheduler {
    private let clock: any JobClock
    /// Base delay before a failed job is retried (S5). The effective retry delay is
    /// `retryBackoff * 2^(failures-1)`, capped at the job's own interval — so a
    /// failure is retried sooner than a full interval, repeated failures back off,
    /// and a perpetually-failing job never runs more often than its interval
    /// (anti-starvation preserved).
    private let retryBackoff: TimeInterval
    private var jobs: [JobID: ScheduledJob] = [:]
    private var lastRun: [JobID: Date] = [:]
    /// Consecutive failures since the last success, per job. Drives retry backoff;
    /// reset to 0 on a successful run.
    private var failureCount: [JobID: Int] = [:]

    public init(clock: any JobClock = SystemJobClock(), retryBackoff: TimeInterval = 300) {
        self.clock = clock
        self.retryBackoff = retryBackoff
    }

    public func register(_ job: ScheduledJob) {
        jobs[job.id] = job
    }

    public func registeredJobIDs() -> [JobID] {
        jobs.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Iterates all registered jobs and runs the ones whose (effective) interval has elapsed since
    /// their last attempt. Throws are caught per-job so one failure doesn't starve the others. The
    /// `lastRun` anchor advances on every attempt; a failed job is re-eligible after a capped
    /// backoff (see `retryBackoff`) rather than waiting a full interval (S5).
    public func runDue() async {
        let now = clock.now()
        for job in jobs.values where shouldRun(job, at: now) {
            await execute(job, at: now)
        }
    }

    /// Force-runs a single job regardless of due-state. Used by `BGTaskScheduler` callbacks where
    /// the system already decided the task is due.
    public func runNow(_ id: JobID) async {
        guard let job = jobs[id] else { return }
        await execute(job, at: clock.now())
    }

    /// Run a job, advancing its `lastRun` anchor and recording success/failure so the
    /// next `shouldRun` applies the retry backoff (S5).
    private func execute(_ job: ScheduledJob, at now: Date) async {
        lastRun[job.id] = now
        do {
            try await job.run(now)
            failureCount[job.id] = 0
        } catch {
            // Swallow (one failure mustn't starve the others) but record it so the
            // job is retried after a backoff. Log via OS log when logger lands.
            failureCount[job.id, default: 0] += 1
        }
    }

    private func shouldRun(_ job: ScheduledJob, at now: Date) -> Bool {
        guard let last = lastRun[job.id] else { return true }
        return now.timeIntervalSince(last) >= effectiveInterval(for: job)
    }

    /// Normal interval when the last run succeeded; otherwise an exponential backoff
    /// from `retryBackoff`, capped at the interval so retries never outpace it.
    private func effectiveInterval(for job: ScheduledJob) -> TimeInterval {
        let failures = failureCount[job.id] ?? 0
        guard failures > 0 else { return job.interval }
        let backoff = retryBackoff * pow(2, Double(failures - 1))
        return min(backoff, job.interval)
    }
}
