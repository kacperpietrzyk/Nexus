import Foundation

/// Stable identifier for scheduled jobs. Add cases as new modules add jobs (Phase 1+ extends with
/// `.indexBuilder`, `.dailyBriefing`, `.embeddingBackfill`, etc — Phase 0f only ships `.tombstonePurge`).
public enum JobID: String, Sendable, Hashable, CaseIterable {
    case tombstonePurge
    case indexBuilder  // reserved — used in 0d follow-up
    case dailyBriefing  // reserved — used in 0e/Phase 1
    case orderRebalance
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
    private var jobs: [JobID: ScheduledJob] = [:]
    private var lastRun: [JobID: Date] = [:]

    public init(clock: any JobClock = SystemJobClock()) {
        self.clock = clock
    }

    public func register(_ job: ScheduledJob) {
        jobs[job.id] = job
    }

    public func registeredJobIDs() -> [JobID] {
        jobs.keys.sorted { $0.rawValue < $1.rawValue }
    }

    /// Iterates all registered jobs and runs the ones whose interval has elapsed since their last
    /// run. Throws are caught per-job so one failure doesn't starve the others. `lastRun` advances
    /// even on throw — we don't want a perpetually-failing job to monopolise scheduler ticks.
    public func runDue() async {
        let now = clock.now()
        for job in jobs.values where shouldRun(job, at: now) {
            lastRun[job.id] = now
            do {
                try await job.run(now)
            } catch {
                // Intentional swallow — log via OS log when logger lands in Phase 1.
            }
        }
    }

    /// Force-runs a single job regardless of due-state. Used by `BGTaskScheduler` callbacks where
    /// the system already decided the task is due.
    public func runNow(_ id: JobID) async {
        guard let job = jobs[id] else { return }
        let now = clock.now()
        lastRun[id] = now
        do {
            try await job.run(now)
        } catch {
            // swallow — same rationale as runDue
        }
    }

    private func shouldRun(_ job: ScheduledJob, at now: Date) -> Bool {
        guard let last = lastRun[job.id] else { return true }
        return now.timeIntervalSince(last) >= job.interval
    }
}
