import Foundation
import NexusCore
import Testing
@testable import NexusAgent

@Suite struct OverloadInsightTests {
    private func day(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    @Test func overloadedDayProducesWarningProposal() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = day("2026-06-15T00:00:00Z")
        let items = [ScheduledItem(id: UUID(), durationMinutes: 600, day: day("2026-06-15T09:00:00Z"))]
        let result = OverloadInsight.detect(
            tasks: items, events: [], days: [date],
            capacity: CapacityModel(dailyCapacityMinutes: 240), calendar: cal)
        #expect(result != nil)
        #expect(result?.rationale.contains("overload") == true || result?.rationale.contains("tight") == true)
    }

    @Test func withinCapacityProducesNil() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = day("2026-06-15T00:00:00Z")
        let items = [ScheduledItem(id: UUID(), durationMinutes: 60, day: day("2026-06-15T09:00:00Z"))]
        let result = OverloadInsight.detect(
            tasks: items, events: [], days: [date],
            capacity: CapacityModel(dailyCapacityMinutes: 240), calendar: cal)
        #expect(result == nil)
    }
}
