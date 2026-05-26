import Foundation
import NexusCore

public enum ScheduleItem: Identifiable, @unchecked Sendable {
    case task(TaskItem)
    case meeting(CalendarEvent)

    public var id: String {
        switch self {
        case .task(let task):
            return "task:\(task.id.uuidString)"
        case .meeting(let event):
            return "meeting:\(event.id)"
        }
    }

    public var start: Date? {
        switch self {
        case .task(let task):
            return task.startAt
        case .meeting(let event):
            return event.start
        }
    }

    public var end: Date? {
        switch self {
        case .task(let task):
            return task.endAt ?? task.dueAt
        case .meeting(let event):
            return event.end
        }
    }
}

public enum ScheduleGrouping {
    public static func group(
        tasks: [TaskItem],
        events: [CalendarEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> (slots: [(Date, [ScheduleItem])], unscheduled: [TaskItem]) {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return ([], [])
        }

        var byMinute: [Date: [ScheduleItem]] = [:]
        var unscheduled: [TaskItem] = []

        for task in tasks {
            guard let start = task.startAt else {
                if taskOccursToday(task, dayStart: dayStart, dayEnd: dayEnd) {
                    unscheduled.append(task)
                }
                continue
            }

            let end = task.endAt ?? task.dueAt ?? start
            guard overlapsDay(start: start, end: end, dayStart: dayStart, dayEnd: dayEnd) else { continue }

            let visibleStart = max(start, dayStart)
            guard let key = minuteStart(for: visibleStart, calendar: calendar) else { continue }
            byMinute[key, default: []].append(.task(task))
        }

        for event in events {
            guard overlapsDay(start: event.start, end: event.end, dayStart: dayStart, dayEnd: dayEnd) else { continue }

            let visibleStart = max(event.start, dayStart)
            guard let key = minuteStart(for: visibleStart, calendar: calendar) else { continue }
            byMinute[key, default: []].append(.meeting(event))
        }

        let slots = byMinute.keys.sorted().map { key in
            (key, byMinute[key] ?? [])
        }

        return (slots, unscheduled)
    }

    public static func isCurrent(item: ScheduleItem, now: Date) -> Bool {
        guard let start = item.start, let end = item.end else {
            return false
        }

        return start <= now && now < end
    }

    private static func minuteStart(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )

        return calendar.date(from: components)
            ?? calendar.dateInterval(of: .minute, for: date)?.start
    }

    private static func taskOccursToday(_ task: TaskItem, dayStart: Date, dayEnd: Date) -> Bool {
        guard let dueAt = task.dueAt else { return false }
        return dueAt >= dayStart && dueAt < dayEnd
    }

    private static func overlapsDay(start: Date, end: Date, dayStart: Date, dayEnd: Date) -> Bool {
        if end > start {
            return end > dayStart && start < dayEnd
        }

        return start >= dayStart && start < dayEnd
    }
}
