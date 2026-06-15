import Foundation
import NexusCore

@MainActor
enum LiquidWeekReferenceData {
    struct Snapshot {
        let days: [Date]
        let events: [CalendarEvent]
        let itemsByDay: [Date: [TimelineItem]]
        let unscheduledTasks: [WeekUnscheduledTask]
        let focusGaps: [DateInterval]

        var primaryFocusGap: DateInterval? { focusGaps.first }
    }

    static func snapshot(days inputDays: [Date], now: Date, calendar: Calendar) -> Snapshot {
        let days = normalizedWeekDays(from: inputDays, now: now, calendar: calendar)
        let events = referenceEvents(days: days, calendar: calendar)
        let itemsByDay = Dictionary(
            uniqueKeysWithValues: days.map { day in
                let items = DayTimelineLayout.items(
                    forDay: day,
                    events: events,
                    blocks: [],
                    calendar: calendar
                )
                return (calendar.startOfDay(for: day), items)
            }
        )
        return Snapshot(
            days: days,
            events: events,
            itemsByDay: itemsByDay,
            unscheduledTasks: [
                WeekUnscheduledTask(
                    id: UUID(uuidString: "D7C48F3E-EA2D-47C9-9B1F-FA75DF3A0311") ?? UUID(),
                    title: "Draft executive rollout brief",
                    projectName: "Design QA",
                    estimatedSeconds: 5_400
                ),
                WeekUnscheduledTask(
                    id: UUID(uuidString: "8FC1D6D7-D09C-4E34-BB2D-604A22345602") ?? UUID(),
                    title: "QA glass states in Projects",
                    projectName: "Liquid UI",
                    estimatedSeconds: 3_600
                ),
                WeekUnscheduledTask(
                    id: UUID(uuidString: "4D9411F8-1E51-4216-8E45-BB7D195B5989") ?? UUID(),
                    title: "Prepare customer follow-up",
                    projectName: "XDR",
                    estimatedSeconds: 2_700
                ),
                WeekUnscheduledTask(
                    id: UUID(uuidString: "689E8E4B-B57E-4A84-BEB7-9648FF0455B5") ?? UUID(),
                    title: "Clean action items from notes",
                    projectName: nil,
                    estimatedSeconds: 1_800
                ),
            ],
            focusGaps: focusGaps(days: days, now: now, calendar: calendar)
        )
    }

    private static func normalizedWeekDays(
        from inputDays: [Date],
        now: Date,
        calendar: Calendar
    ) -> [Date] {
        if inputDays.count == 7 {
            return inputDays.map { calendar.startOfDay(for: $0) }
        }
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = interval?.start ?? calendar.startOfDay(for: now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // swiftlint:disable:next function_body_length
    private static func referenceEvents(days: [Date], calendar: Calendar) -> [CalendarEvent] {
        [
            allDay(
                id: "ref-launch-plan",
                title: "[Karolina] rollout plan",
                day: days[safe: 2] ?? days[0],
                colorHex: "#F7B955",
                calendar: calendar
            ),
            allDay(
                id: "ref-pilot-qa",
                title: "[Karolina] pilot QA",
                day: days[safe: 3] ?? days[0],
                colorHex: "#F7B955",
                calendar: calendar
            ),
            allDay(
                id: "ref-pilot-wroclaw",
                title: "[Karolina] pilot Wroclaw",
                day: days[safe: 4] ?? days[0],
                colorHex: "#F7B955",
                calendar: calendar
            ),
            event(
                id: "ref-scope",
                title: "Sycope pods planning",
                day: days[0],
                startHour: 11,
                endHour: 12,
                colorHex: "#2997FF",
                calendar: calendar
            ),
            event(
                id: "ref-dlp",
                title: "DLP - kick-off",
                day: days[safe: 1] ?? days[0],
                startHour: 13,
                endHour: 14.5,
                colorHex: "#2997FF",
                calendar: calendar
            ),
            event(
                id: "ref-soc",
                title: "Spotkanie SOC",
                day: days[safe: 2] ?? days[0],
                startHour: 10,
                endHour: 11,
                colorHex: "#37D67A",
                calendar: calendar
            ),
            event(
                id: "ref-review-a",
                title: "Harmony XDR review",
                day: days[safe: 4] ?? days[0],
                startHour: 10,
                endHour: 11,
                colorHex: "#9B72FF",
                calendar: calendar
            ),
            event(
                id: "ref-review-b",
                title: "Endpoint rollout sync",
                day: days[safe: 4] ?? days[0],
                startHour: 10.5,
                endHour: 11.5,
                colorHex: "#F06767",
                calendar: calendar
            ),
            event(
                id: "ref-hajnowka",
                title: "Hajnowka XDR - Podsumowanie",
                day: days[safe: 4] ?? days[0],
                startHour: 15.5,
                endHour: 16,
                colorHex: "#2997FF",
                calendar: calendar
            ),
            event(
                id: "ref-family",
                title: "[Wspolnie] Zakupy",
                day: days[safe: 6] ?? days[0],
                startHour: 9,
                endHour: 9.75,
                colorHex: "#F7B955",
                calendar: calendar
            ),
            event(
                id: "ref-catchup",
                title: "[Wspolnie] Coffee",
                day: days[safe: 6] ?? days[0],
                startHour: 9.5,
                endHour: 10.25,
                colorHex: "#F7B955",
                calendar: calendar
            ),
            event(
                id: "ref-sunday",
                title: "[Wspolnie] Sprint prep",
                day: days[safe: 6] ?? days[0],
                startHour: 10,
                endHour: 10.7,
                colorHex: "#F7B955",
                calendar: calendar
            ),
        ]
    }

    private static func focusGaps(days: [Date], now: Date, calendar: Calendar) -> [DateInterval] {
        let targetDay = days.first { calendar.isDate($0, inSameDayAs: now) } ?? days[safe: 4] ?? days[0]
        return [
            interval(day: targetDay, startHour: 13.65, endHour: 15.5, calendar: calendar),
            interval(day: targetDay, startHour: 16, endHour: 18, calendar: calendar),
        ].compactMap { $0 }
    }

    private static func allDay(
        id: String,
        title: String,
        day: Date,
        colorHex: String,
        calendar: Calendar
    ) -> CalendarEvent {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return CalendarEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            calendarColorHex: colorHex,
            isAllDay: true
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func event(
        id: String,
        title: String,
        day: Date,
        startHour: Double,
        endHour: Double,
        colorHex: String,
        calendar: Calendar
    ) -> CalendarEvent {
        let start = date(day: day, hour: startHour, calendar: calendar)
        let end = date(day: day, hour: endHour, calendar: calendar)
        return CalendarEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            attendees: [
                .init(name: "Kacper Pietrzyk", responseStatus: .accepted, role: .required, isCurrentUser: true),
                .init(name: "Karolina", responseStatus: .accepted, role: .required),
            ],
            isVideoCall: true,
            calendarColorHex: colorHex
        )
    }

    private static func interval(
        day: Date,
        startHour: Double,
        endHour: Double,
        calendar: Calendar
    ) -> DateInterval? {
        let start = date(day: day, hour: startHour, calendar: calendar)
        let end = date(day: day, hour: endHour, calendar: calendar)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func date(day: Date, hour: Double, calendar: Calendar) -> Date {
        let wholeHours = Int(hour)
        let minutes = Int((hour - Double(wholeHours)) * 60)
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(
            byAdding: DateComponents(hour: wholeHours, minute: minutes),
            to: dayStart
        ) ?? dayStart
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
