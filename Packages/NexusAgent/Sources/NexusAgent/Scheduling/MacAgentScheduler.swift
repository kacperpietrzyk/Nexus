import Foundation
import os

#if os(macOS) && canImport(ServiceManagement)
import ServiceManagement
#endif

@MainActor
public final class MacAgentScheduler: AgentScheduler {
    private let scheduleStore: AgentScheduleStore
    private let onFire: @MainActor (UUID) async -> Void
    private let vacationModeGate: VacationModeGate
    private let tickInterval: Duration
    private let shouldInstallLoginItem: Bool
    private var tickTask: Task<Void, Never>?
    private var lastFireSlotByID: [UUID: Date] = [:]
    private let logger = Logger(
        subsystem: "com.kacperpietrzyk.nexus.agent",
        category: "MacAgentScheduler"
    )

    public convenience init(
        scheduleStore: AgentScheduleStore,
        onFire: @escaping @MainActor (UUID) async -> Void,
        vacationModeGate: VacationModeGate = .init(),
        tickInterval: Duration = .seconds(30)
    ) {
        self.init(
            scheduleStore: scheduleStore,
            onFire: onFire,
            vacationModeGate: vacationModeGate,
            tickInterval: tickInterval,
            shouldInstallLoginItem: true
        )
    }

    init(
        scheduleStore: AgentScheduleStore,
        onFire: @escaping @MainActor (UUID) async -> Void,
        vacationModeGate: VacationModeGate = .init(),
        tickInterval: Duration = .seconds(30),
        shouldInstallLoginItem: Bool
    ) {
        self.scheduleStore = scheduleStore
        self.onFire = onFire
        self.vacationModeGate = vacationModeGate
        self.tickInterval = tickInterval
        self.shouldInstallLoginItem = shouldInstallLoginItem
    }

    public func start() async {
        if shouldInstallLoginItem {
            installLoginItemIfNeeded()
        }
        tickTask?.cancel()

        let interval = tickInterval
        tickTask = Task { [weak self, interval] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func reschedule(_ scheduleID: UUID) async {
        lastFireSlotByID.removeValue(forKey: scheduleID)
    }

    public func suspend(_ scheduleID: UUID) async {
        lastFireSlotByID[scheduleID] = .distantFuture
    }

    public func suspendAll() async {
        tickTask?.cancel()
        tickTask = nil
    }

    func tickForTesting(now: Date) async {
        await tick(now: now)
    }

    private func tick(now: Date = .now) async {
        let schedules = (try? scheduleStore.allActive()) ?? []
        let calendar = Calendar(identifier: .gregorian)
        guard let fireSlot = Self.fireSlot(for: now, calendar: calendar) else { return }

        for schedule in schedules where schedule.enabled {
            guard let cron = try? CronExpression(schedule.cronExpression),
                cron.matches(now, calendar: calendar)
            else { continue }

            let lastFireSlot = lastFireSlotByID[schedule.id]
            guard lastFireSlot != .distantFuture else { continue }
            guard lastFireSlot != fireSlot else { continue }

            lastFireSlotByID[schedule.id] = fireSlot
            guard vacationModeGate.shouldFire(scheduleID: schedule.id) else {
                recordSkipped(schedule: schedule, now: now)
                continue
            }
            await onFire(schedule.id)
        }
    }

    private func recordSkipped(schedule: AgentSchedule, now: Date) {
        schedule.lastRunAt = now
        schedule.lastRunStatus = .skipped
        schedule.lastRunResultRef = nil
        try? scheduleStore.touch(id: schedule.id, now: now)
    }

    private static func fireSlot(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components)
    }

    private func installLoginItemIfNeeded() {
        #if os(macOS) && canImport(ServiceManagement)
        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered:
            do {
                try service.register()
                logger.info("Registered LoginItem with SMAppService")
            } catch {
                logger.warning(
                    "LoginItem registration failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        case .enabled, .requiresApproval:
            return
        default:
            return
        }
        #endif
    }
}
