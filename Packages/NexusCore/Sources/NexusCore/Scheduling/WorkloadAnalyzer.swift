import Foundation

/// A unit of scheduled work on a given calendar day (task occurrence).
public struct ScheduledItem: Sendable, Equatable {
    public let id: UUID
    public let durationMinutes: Int
    public let day: Date
    public init(id: UUID, durationMinutes: Int, day: Date) {
        self.id = id; self.durationMinutes = max(0, durationMinutes); self.day = day
    }
}

public struct DayLoad: Sendable, Equatable {
    public let day: Date  // start-of-day
    public let scheduledMinutes: Int
    public let capacityMinutes: Int
    public var isOverloaded: Bool { scheduledMinutes > capacityMinutes }
    public init(day: Date, scheduledMinutes: Int, capacityMinutes: Int) {
        self.day = day; self.scheduledMinutes = scheduledMinutes; self.capacityMinutes = capacityMinutes
    }
}

/// Pure arithmetic: per-day sum of task + event minutes vs capacity. No reasoning, no model.
public struct WorkloadAnalyzer: Sendable {
    public let calendar: Calendar
    public init(calendar: Calendar = .current) { self.calendar = calendar }

    public func analyze(tasks: [ScheduledItem], events: [CalendarEvent], days: [Date], capacity: CapacityModel) -> [DayLoad] {
        days.map { rawDay in
            let sod = calendar.startOfDay(for: rawDay)
            let taskMin =
                tasks
                .filter { calendar.isDate($0.day, inSameDayAs: sod) }
                .reduce(0) { $0 + $1.durationMinutes }
            let eventMin =
                events
                .filter { !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: sod) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
            return DayLoad(day: sod, scheduledMinutes: taskMin + eventMin, capacityMinutes: capacity.dailyCapacityMinutes)
        }
    }
}
