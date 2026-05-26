import Foundation
import os

#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

@MainActor
public protocol BGTaskSchedulerInterface: Sendable {
    func submit(identifier: String, earliestBeginDate: Date?) throws
}

#if os(iOS) && canImport(BackgroundTasks)
@MainActor
public struct SystemBGTaskScheduler: BGTaskSchedulerInterface {
    public init() {}

    public func submit(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try BGTaskScheduler.shared.submit(request)
    }
}
#endif

@MainActor
public final class IOSAgentScheduler: AgentScheduler {
    public static let bgTaskIdentifier = "nexus.agent.scheduleRun"

    private let scheduleStore: AgentScheduleStore
    private let onFire: @MainActor (UUID) async -> Void
    private let vacationModeGate: VacationModeGate
    private let bgScheduler: BGTaskSchedulerInterface
    private var didSubmitInitialBackgroundRequest = false
    private var lastCatchUpDueByID: [UUID: Date] = [:]
    private var inFlightDueByID: [UUID: Date] = [:]
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "IOSAgentScheduler"
    )

    public init(
        scheduleStore: AgentScheduleStore,
        onFire: @escaping @MainActor (UUID) async -> Void,
        vacationModeGate: VacationModeGate = .init(),
        bgScheduler: BGTaskSchedulerInterface
    ) {
        self.scheduleStore = scheduleStore
        self.onFire = onFire
        self.vacationModeGate = vacationModeGate
        self.bgScheduler = bgScheduler
    }

    public func start() async {
        if !didSubmitInitialBackgroundRequest {
            didSubmitInitialBackgroundRequest = submitBackgroundRequest()
        }
        await foregroundCatchUp()
    }

    public func runBackgroundTask(now: Date = .now) async {
        _ = submitBackgroundRequest(now: now)
        await foregroundCatchUp(now: now)
    }

    public func reschedule(_ scheduleID: UUID) async {
        lastCatchUpDueByID.removeValue(forKey: scheduleID)
        inFlightDueByID.removeValue(forKey: scheduleID)
        _ = submitBackgroundRequest()
    }

    public func suspend(_ scheduleID: UUID) async {}

    public func suspendAll() async {}

    public func foregroundCatchUp(now: Date = .now) async {
        guard !Task.isCancelled else { return }

        let schedules = (try? scheduleStore.allActive()) ?? []
        let calendar = Calendar(identifier: .gregorian)

        for schedule in schedules where schedule.enabled {
            guard !Task.isCancelled else { return }
            guard let cron = try? CronExpression(schedule.cronExpression) else { continue }
            let last = schedule.lastRunAt ?? schedule.createdAt
            guard let due = cron.next(after: last, calendar: calendar), due <= now else { continue }
            guard lastCatchUpDueByID[schedule.id] != due else { continue }
            guard inFlightDueByID[schedule.id] != due else { continue }
            guard vacationModeGate.shouldFire(scheduleID: schedule.id) else {
                recordSkipped(schedule: schedule, due: due, now: now)
                continue
            }

            inFlightDueByID[schedule.id] = due
            guard !Task.isCancelled else {
                inFlightDueByID.removeValue(forKey: schedule.id)
                return
            }
            await onFire(schedule.id)
            inFlightDueByID.removeValue(forKey: schedule.id)
            guard !Task.isCancelled else { return }
            guard let updatedSchedule = try? scheduleStore.get(id: schedule.id),
                let lastRunAt = updatedSchedule.lastRunAt,
                lastRunAt >= due
            else { continue }

            lastCatchUpDueByID[schedule.id] = due
        }
    }

    private func recordSkipped(schedule: AgentSchedule, due: Date, now: Date) {
        schedule.lastRunAt = now
        schedule.lastRunStatus = .skipped
        schedule.lastRunResultRef = nil
        lastCatchUpDueByID[schedule.id] = due
        try? scheduleStore.touch(id: schedule.id, now: now)
    }

    @discardableResult
    private func submitBackgroundRequest(now: Date = .now) -> Bool {
        do {
            try bgScheduler.submit(
                identifier: Self.bgTaskIdentifier,
                earliestBeginDate: nextBackgroundBeginDate(now: now)
            )
            return true
        } catch {
            logger.warning(
                "Agent BGTaskScheduler submit failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func nextBackgroundBeginDate(now: Date) -> Date? {
        let schedules = (try? scheduleStore.allActive()) ?? []
        let calendar = Calendar(identifier: .gregorian)
        let nextFire =
            schedules
            .filter(\.enabled)
            .compactMap { schedule -> Date? in
                guard let cron = try? CronExpression(schedule.cronExpression) else { return nil }
                return cron.next(after: now, calendar: calendar)
            }
            .min()

        guard let nextFire else { return nil }
        return max(now, nextFire.addingTimeInterval(-3600))
    }
}
