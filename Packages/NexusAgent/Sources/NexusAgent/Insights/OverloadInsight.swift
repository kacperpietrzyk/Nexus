import Foundation
import NexusCore

public enum OverloadInsight {
    /// Pure: returns a warning Proposal when any day exceeds capacity, else nil. No model.
    public static func detect(
        tasks: [ScheduledItem],
        events: [CalendarEvent],
        days: [Date],
        capacity: CapacityModel,
        calendar: Calendar = .current
    ) -> Proposal? {
        let loads = WorkloadAnalyzer(calendar: calendar)
            .analyze(tasks: tasks, events: events, days: days, capacity: capacity)
        let overloaded = loads.filter { $0.isOverloaded }
        guard !overloaded.isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM"
        let dayStrings = overloaded.map { "\(fmt.string(from: $0.day)) (\($0.scheduledMinutes / 60)h)" }
        let names = dayStrings.joined(separator: ", ")
        let capacityHours = capacity.dailyCapacityMinutes / 60
        let rationale =
            "\(overloaded.count) day(s) look overloaded vs your \(capacityHours)h capacity: \(names)."
        // v1: advisory only — no auto-mutations (rebalancing suggestions can be added later).
        let previews = overloaded.map {
            ProposalPreview(summary: "\(fmt.string(from: $0.day)): \($0.scheduledMinutes / 60)h scheduled")
        }
        return Proposal(rationale: rationale, mutations: [], previews: previews)
    }

    public static func dedupeKey(for days: [DayLoad]) -> String {
        let overloadedDays = days.filter(\.isOverloaded)
        let keys = overloadedDays.map { ISO8601DateFormatter().string(from: $0.day) }
        return "overload:" + keys.joined(separator: ",")
    }
}
