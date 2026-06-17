import NexusCore
import Observation
import SwiftData
import SwiftUI

/// Holder for the Today deadline-risk signal (spec §19.1 D1).
///
/// Extracted out of `TodayDashboard`'s view state so the projection — the
/// proven hottest path on a return-to-Today appear (a full `DeadlineRiskProjector`
/// run over ALL open tasks) — carries a skip-redundant-reload gate that an
/// unchanged return-navigation early-returns through, exactly mirroring
/// `LiquidTodayModel`'s `reload()` snapshot gate. `TodayDashboard` reads the
/// `summary`/`topTask` forwarders so the banner copy is byte-for-byte unchanged.
///
/// `@Observable @MainActor` (not view `@State`) so the gate provenance + the
/// `deadlineRiskComputeCount` characterization counter are unit-testable against
/// an in-memory `ModelContainer`, the same way `LiquidTodayModel` is tested.
@MainActor
@Observable
public final class TodayDeadlineRiskModel {

    /// Forward-looking deadline-risk signal — default empty so the pre-compute
    /// banner render matches the old `@State` initializer exactly.
    public private(set) var summary = DeadlineRiskSummary(atRiskTaskIDs: [], tightTaskIDs: [], mostUrgent: nil)
    /// The most-urgent risk task resolved for the banner copy + tap target.
    public private(set) var topTask: TaskItem?

    /// Test-visible count of full deadline-risk projections. A gated
    /// (early-return) return-navigation leaves this unchanged — drives the
    /// characterization that proves the gate skips the recompute.
    public private(set) var deadlineRiskComputeCount = 0

    // Skip-redundant-reload gate provenance: the day-start + calendar-visibility
    // the held projection was built for, plus a dirty flag the real-change
    // triggers raise. A return-navigation matching all three early-returns.
    private var loadedDayStart: Date?
    private var loadedCalendarEventsEnabled: Bool?
    private var needsReload = true

    public init() {}

    /// Marks the held projection stale so the next `refresh()` recomputes
    /// (store-change hook, scene-active, in-screen mutation cascades).
    public func markDirty() {
        needsReload = true
    }

    /// Horizon (days) the risk projection looks ahead. Matches the
    /// `schedule.deadline_risks` agent-tool default (spec §19.1).
    static let horizonDays = 14

    /// Refresh the deadline-risk signal from the current store + calendar horizon.
    /// Same body as the old `TodayDashboard.refreshDeadlineRisk(now:)`, fronted by
    /// a gate: an unchanged return-navigation (clean dirty flag, same day, same
    /// calendar-visibility) early-returns and reuses the held `summary`/`topTask`
    /// — pixel-identical. `markDirty`, a calendar toggle, or a midnight rollover
    /// all bypass the gate and force a fresh projection (the projection is
    /// idempotent over the live store, so caching is valid).
    public func refresh(
        modelContext: ModelContext,
        calendarProvider: any CalendarEventProviding,
        calendarEventsEnabled: Bool,
        now: Date
    ) async {
        let dayStart = Calendar.current.startOfDay(for: now)
        let snapshotStillValid =
            !needsReload && loadedDayStart == dayStart
            && loadedCalendarEventsEnabled == calendarEventsEnabled
        if snapshotStillValid { return }

        let days = Self.horizonDays
        // Obstacles across the whole horizon (not just today) so the free-time
        // math sees future events; `[]` when the feed is off or access absent.
        var events: [CalendarEvent] = []
        let prefs = UserDefaultsCalendarPreferencesStore().load()
        if calendarEventsEnabled {
            let end = now.addingTimeInterval(TimeInterval(days * 24 * 60 * 60))
            let fetched = (try? await calendarProvider.eventsBetween(start: now, end: end)) ?? []
            // #6: deadline-risk free-time math must ignore disabled calendars too.
            events = prefs.visibleEvents(fetched)
        }
        let risks = DeadlineRiskProjector.project(
            context: modelContext,
            events: events,
            prefs: prefs,
            horizon: TimeInterval(days * 24 * 60 * 60),
            now: now,
            calendar: .current
        )
        let resolvedSummary = DeadlineRiskSummary.make(from: risks)
        deadlineRiskComputeCount += 1
        summary = resolvedSummary
        topTask = Self.resolveTopTask(summary: resolvedSummary, modelContext: modelContext)
        // Record provenance + clear the dirty flag so the next unchanged
        // return-navigation hits the early-return above.
        loadedDayStart = dayStart
        loadedCalendarEventsEnabled = calendarEventsEnabled
        needsReload = false
    }

    /// Resolve the single most-urgent risk task (for the banner copy + tap
    /// target), or nil when nothing is under pressure.
    static func resolveTopTask(
        summary: DeadlineRiskSummary,
        modelContext: ModelContext
    ) -> TaskItem? {
        guard let taskID = summary.mostUrgent?.taskID else { return nil }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }
}
