import Foundation
import NexusCore

/// A meeting that needs decompose evaluation.
public struct MeetingDecomposeCandidate: Sendable {
    public let id: UUID
    public let summary: String
    public let actionItemIDs: [UUID]

    public init(id: UUID, summary: String, actionItemIDs: [UUID]) {
        self.id = id
        self.summary = summary
        self.actionItemIDs = actionItemIDs
    }
}

/// Foreground-driven orchestration hub for proactive insights.
///
/// On app foreground, the app calls `runDueInsights(now:)`. The coordinator
/// runs each of the three insight checks gated by cooldown/dedupe and populates
/// the `PendingInsightStore`. Each check is wrapped independently so a failure
/// in one does not prevent the others from running.
///
/// v1: foreground-only; no `BGTaskScheduler`/`AgentScheduler` usage.
@MainActor
public final class InsightCoordinator {
    // MARK: - Dependencies

    private let cooldown: InsightCooldownStore
    private let pending: PendingInsightStore

    // Data providers
    private let tasksProvider: @MainActor () -> [ScheduledItem]
    private let eventsProvider: @MainActor () async -> [CalendarEvent]
    private let capacityProvider: @MainActor () -> CapacityModel
    private let meetingsProvider: @MainActor () -> [MeetingDecomposeCandidate]

    // Optional model bits
    private let dayPlanRunner: SkillRunner?
    private let dayPlanNumbers: @MainActor () -> String
    private let makeDecomposeCoordinator: @MainActor () -> MeetingDecomposeCoordinator

    private let calendar: Calendar

    // MARK: - Init

    public init(
        cooldown: InsightCooldownStore,
        pending: PendingInsightStore,
        tasks: @escaping @MainActor () -> [ScheduledItem],
        events: @escaping @MainActor () async -> [CalendarEvent],
        capacity: @escaping @MainActor () -> CapacityModel,
        meetingsNeedingDecompose: @escaping @MainActor () -> [MeetingDecomposeCandidate],
        dayPlanRunner: SkillRunner?,
        dayPlanNumbers: @escaping @MainActor () -> String,
        makeDecomposeCoordinator: @escaping @MainActor () -> MeetingDecomposeCoordinator,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        _ = now  // reserved for callers; runDueInsights(now:) accepts time explicitly
        self.cooldown = cooldown
        self.pending = pending
        self.tasksProvider = tasks
        self.eventsProvider = events
        self.capacityProvider = capacity
        self.meetingsProvider = meetingsNeedingDecompose
        self.dayPlanRunner = dayPlanRunner
        self.dayPlanNumbers = dayPlanNumbers
        self.makeDecomposeCoordinator = makeDecomposeCoordinator
        self.calendar = calendar
    }

    // MARK: - Main entry point

    /// Runs all three insight checks. Each check is independently failure-isolated.
    public func runDueInsights(now: Date) async {
        let tasks = tasksProvider()
        let events = await eventsProvider()
        let cap = capacityProvider()

        await runOverloadCheck(tasks: tasks, events: events, capacity: cap, now: now)
        await runDayPlanCheck(now: now)
        await runMeetingDecomposeCheck(now: now)
    }

    // MARK: - Overload (6 h cooldown, skeleton-only)

    private func runOverloadCheck(
        tasks: [ScheduledItem],
        events: [CalendarEvent],
        capacity: CapacityModel,
        now: Date
    ) async {
        // Build the next-7-days window.
        let days: [Date] = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))
        }

        // Compute loads for dedupeKey; detect() recomputes internally but is pure.
        let loads = WorkloadAnalyzer(calendar: calendar)
            .analyze(tasks: tasks, events: events, days: days, capacity: capacity)
        let key = OverloadInsight.dedupeKey(for: loads)

        guard cooldown.shouldFire(key: key, cooldown: 6 * 3_600) else { return }

        guard
            let proposal = OverloadInsight.detect(
                tasks: tasks,
                events: events,
                days: days,
                capacity: capacity,
                calendar: calendar)
        else { return }

        pending.add(kind: "overload", dedupeKey: key, proposal: proposal)
        cooldown.record(key: key)
    }

    // MARK: - Day plan (12 h / per-day-bucket cooldown)

    private func runDayPlanCheck(now: Date) async {
        guard let runner = dayPlanRunner else { return }

        let dayKey = dayPlanKey(for: now)
        guard cooldown.shouldFire(key: dayKey, cooldown: 12 * 3_600) else { return }

        do {
            let proposal = try await DayPlanInsight.proposal(
                runner: runner,
                summaryNumbers: dayPlanNumbers(),
                focus: ContextFocus(),
                now: now)
            pending.add(kind: "day_plan", dedupeKey: dayKey, proposal: proposal)
            cooldown.record(key: dayKey)
        } catch {
            // A model failure must not block subsequent checks.
        }
    }

    // MARK: - Meeting decompose (24 h per-meeting cooldown)

    private func runMeetingDecomposeCheck(now: Date) async {
        let meetings = meetingsProvider()
        for meeting in meetings {
            let key = MeetingDecomposeInsight.dedupeKey(meetingID: meeting.id)
            guard cooldown.shouldFire(key: key, cooldown: 24 * 3_600) else { continue }

            do {
                let coordinator = makeDecomposeCoordinator()
                guard
                    let proposal = try await MeetingDecomposeInsight.proposalIfEligible(
                        summary: meeting.summary,
                        actionItemIDs: meeting.actionItemIDs,
                        focus: ContextFocus(),
                        coordinator: coordinator)
                else { continue }

                pending.add(kind: "meeting_decompose", dedupeKey: key, proposal: proposal)
                cooldown.record(key: key)
            } catch {
                // A per-meeting failure must not block other meetings or other checks.
            }
        }
    }

    // MARK: - Private helpers

    private func dayPlanKey(for date: Date) -> String {
        let sod = calendar.startOfDay(for: date)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        return "day_plan:" + iso.string(from: sod)
    }
}
