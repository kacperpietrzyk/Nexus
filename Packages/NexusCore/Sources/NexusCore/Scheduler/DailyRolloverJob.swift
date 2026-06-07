import Foundation
import SwiftData

/// Daily auto-rollover (spec §10): unfinished due-today / overdue open tasks have
/// their `dueAt` pushed to the next workday (à la Linear), and dead `proposed`
/// blocks (past, never accepted) are swept. Mirrors the `OrderRebalanceJob`
/// pattern: a fresh `ModelContext` per run, no long-lived container reference.
///
/// Gated by `CalendarPreferences.rolloverEnabled`; when disabled the run is a
/// no-op. The date math (`nextWorkday`) is a pure, deterministic, timezone-explicit
/// helper so it is unit-testable without a store.
public enum DailyRolloverJob {
    public static let dailyInterval: TimeInterval = 60 * 60 * 24

    public static func makeJob(
        containerProvider: @escaping @Sendable () -> ModelContainer,
        preferencesProvider: @escaping @Sendable () -> CalendarPreferences = {
            UserDefaultsCalendarPreferencesStore().load()
        }
    ) -> ScheduledJob {
        ScheduledJob(id: .dailyRollover, interval: dailyInterval) { now in
            let prefs = preferencesProvider()
            guard prefs.rolloverEnabled else { return }
            let container = containerProvider()
            try await rollover(in: container, now: now, calendar: .current)
        }
    }

    /// The next workday at or after `date + 1 day` (skips Saturday/Sunday). Pure +
    /// deterministic; `calendar` is injected (never `Calendar.current`).
    public static func nextWorkday(after date: Date, calendar: Calendar) -> Date {
        var candidate = calendar.startOfDay(for: date)
        repeat {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        } while calendar.isDateInWeekend(candidate)
        return candidate
    }

    @MainActor
    static func rollover(in container: ModelContainer, now: Date, calendar: Calendar) async throws {
        let context = ModelContext(container)
        let startOfTomorrow =
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)

        // Open tasks due before tomorrow (overdue + due-today) roll to the next workday.
        let openRaw = TaskStatus.open.rawValue
        let dueDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.deletedAt == nil
                    && task.statusRaw == openRaw
                    && task.dueAt != nil
            }
        )
        let target = nextWorkday(after: now, calendar: calendar)
        let dueTasks = try context.fetch(dueDescriptor).filter { ($0.dueAt ?? .distantFuture) < startOfTomorrow }
        for task in dueTasks {
            // Preserve the original time-of-day on the new date.
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: task.dueAt ?? now)
            let rolled = calendar.date(
                bySettingHour: timeComponents.hour ?? 9,
                minute: timeComponents.minute ?? 0,
                second: timeComponents.second ?? 0,
                of: target
            )
            task.dueAt = rolled ?? target
            task.updatedAt = now
        }

        // Sweep dead proposed blocks: past, never accepted (orphaned suggestions).
        let proposedRaw = ScheduledBlockStatus.proposed.rawValue
        let startOfToday = calendar.startOfDay(for: now)
        let staleDescriptor = FetchDescriptor<ScheduledBlock>(
            predicate: #Predicate { block in
                block.deletedAt == nil
                    && block.statusRaw == proposedRaw
                    && block.end < startOfToday
            }
        )
        let blocks = ScheduledBlockRepository(context: context, now: { now })
        for block in try context.fetch(staleDescriptor) {
            try blocks.softDelete(block)
        }

        try context.save()
    }
}
