import Foundation
import NexusCore

/// Formats a `TaskItem.dueAt` (and optional `startAt`) into a compact label
/// the row UI renders as a chip. Pure logic — calendar + now are injected so
/// tests can pin output deterministically.
public enum DueChipFormatter {

    /// Five-state result. Equatable so view tests can match exactly.
    public enum DueChipLabel: Equatable, Sendable {
        case noDate
        case overdue(daysLate: Int)
        case today(timeOfDay: String?)
        case tomorrow(timeOfDay: String?)
        case future(date: String, timeOfDay: String?)
    }

    public static func label(
        for task: TaskItem,
        now: Date,
        calendar: Calendar
    ) -> DueChipLabel {
        guard let dueAt = task.dueAt else { return .noDate }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDue = calendar.startOfDay(for: dueAt)
        let dayDelta = calendar.dateComponents([.day], from: startOfToday, to: startOfDue).day ?? 0
        let timeOfDay = formatTimeOfDay(task.startAt, calendar: calendar)

        if dayDelta < 0 {
            return .overdue(daysLate: -dayDelta)
        }
        if dayDelta == 0 {
            return .today(timeOfDay: timeOfDay)
        }
        if dayDelta == 1 {
            return .tomorrow(timeOfDay: timeOfDay)
        }
        return .future(date: formatShortDate(dueAt, calendar: calendar), timeOfDay: timeOfDay)
    }

    private static func formatTimeOfDay(_ date: Date?, calendar: Calendar) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func formatShortDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
