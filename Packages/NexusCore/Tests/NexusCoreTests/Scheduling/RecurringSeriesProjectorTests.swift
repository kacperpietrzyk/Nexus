import Foundation
import Testing

@testable import NexusCore

@Suite("RecurringSeriesProjector")
struct RecurringSeriesProjectorTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // Friday 2026-06-05 09:00 UTC — inside the default 09:00–18:00 window
    // (the existing CalendarViewModelTests anchor).
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    /// Fri Jun 5 00:00 → Fri Jun 12 00:00 UTC (a 7-day week window).
    private var weekWindow: DateInterval {
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: start.addingTimeInterval(7 * 86_400))
    }

    private func makeDailyTask(title: String = "standup", estimateSeconds: Int = 3600) -> TaskItem {
        let task = TaskItem(
            title: title,
            dueAt: now.addingTimeInterval(3600),  // today 10:00
            recurrenceRule: "FREQ=DAILY"
        )
        task.estimatedDurationSeconds = estimateSeconds
        task.durationSourceRaw = DurationSource.explicit.rawValue
        return task
    }

    @MainActor
    @Test("daily recurring task projects one preview per future day of the window, never today")
    func dailyProjectsFutureDays() {
        let task = makeDailyTask()
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [task],
            events: [],
            obstacles: [],
            prefs: .default,
            window: weekWindow,
            now: now,
            calendar: calendar
        )

        // Sat Jun 6 … Thu Jun 11 = 6 future days in the window.
        #expect(previews.count == 6)
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = todayStart.addingTimeInterval(86_400)
        #expect(previews.allSatisfy { $0.start >= tomorrowStart })
        #expect(previews.allSatisfy { $0.taskID == task.id })
        #expect(previews.allSatisfy { $0.title == "standup" })
        // Slot-fill from the working window start: 09:00–10:00 each day.
        let first = previews.min(by: { $0.start < $1.start })
        #expect(first?.start == tomorrowStart.addingTimeInterval(9 * 3600))
        #expect(first?.end == tomorrowStart.addingTimeInterval(10 * 3600))
        // Occurrence dates carry the rule's own time-of-day (10:00).
        #expect(first?.occurrenceDate == tomorrowStart.addingTimeInterval(10 * 3600))
    }

    @MainActor
    @Test("completion-anchored series project nothing — future dates depend on completion time")
    func completionAnchoredExcluded() {
        let task = makeDailyTask()
        task.recurrenceRule = "FREQ=DAILY;ANCHOR=COMPLETION"
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [task], events: [], obstacles: [], prefs: .default,
            window: weekWindow, now: now, calendar: calendar
        )

        #expect(previews.isEmpty)
    }

    @MainActor
    @Test("templates, done tasks, non-recurring and dueAt-less tasks never project")
    func ineligibleTasksExcluded() {
        let template = makeDailyTask(title: "template")
        template.isTemplate = true
        let done = makeDailyTask(title: "done")
        done.statusRaw = TaskStatus.done.rawValue
        let plain = TaskItem(title: "plain", dueAt: now.addingTimeInterval(3600))
        let noDue = TaskItem(title: "no due", recurrenceRule: "FREQ=DAILY")
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [template, done, plain, noDue], events: [], obstacles: [],
            prefs: .default, window: weekWindow, now: now, calendar: calendar
        )

        #expect(previews.isEmpty)
    }

    @MainActor
    @Test("horizon 0 disables projection entirely")
    func zeroHorizonDisables() {
        let task = makeDailyTask()
        var prefs = CalendarPreferences.default
        prefs.seriesPreviewHorizonDays = 0
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [task], events: [], obstacles: [], prefs: prefs,
            window: weekWindow, now: now, calendar: calendar
        )

        #expect(previews.isEmpty)
    }

    @MainActor
    @Test("horizon clamps the window: 2-day horizon projects only the next two days")
    func horizonClampsWindow() {
        let task = makeDailyTask()
        var prefs = CalendarPreferences.default
        prefs.seriesPreviewHorizonDays = 2
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [task], events: [], obstacles: [], prefs: prefs,
            window: weekWindow, now: now, calendar: calendar
        )

        #expect(previews.count == 2)
    }

    @MainActor
    @Test("COUNT-capped rule stops projecting after the remaining occurrences")
    func countCapRespected() {
        let task = makeDailyTask()
        task.recurrenceRule = "FREQ=DAILY;COUNT=3"
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [task], events: [], obstacles: [], prefs: .default,
            window: weekWindow, now: now, calendar: calendar
        )

        // Base instance counts as occurrence 1 of 3 → exactly 2 future previews.
        #expect(previews.count == 2)
    }

    @MainActor
    @Test("a spawned open instance due on a future day previews on its own day (no past enumeration)")
    func spawnedFutureInstancePreviews() {
        // Mimic post-completion state: parent done, spawn open due tomorrow 10:00.
        let parent = makeDailyTask(title: "series")
        parent.statusRaw = TaskStatus.done.rawValue
        parent.lastCompletedAt = now
        let spawn = TaskItem(
            title: "series",
            dueAt: now.addingTimeInterval(86_400 + 3600),
            recurrenceRule: "FREQ=DAILY",
            recurrenceParentId: parent.id
        )
        spawn.estimatedDurationSeconds = 3600
        spawn.durationSourceRaw = DurationSource.explicit.rawValue
        let projector = RecurringSeriesProjector()

        let previews = projector.preview(
            tasks: [parent, spawn], events: [], obstacles: [], prefs: .default,
            window: weekWindow, now: now, calendar: calendar
        )

        // Tomorrow (the spawn's own due day) + the 5 days after = 6, all bound to the spawn.
        #expect(previews.count == 6)
        #expect(previews.allSatisfy { $0.taskID == spawn.id })
        #expect(previews.allSatisfy { $0.seriesID == parent.id })
    }
}
