import Foundation
import Testing

@testable import NexusCore

@Suite("RRule")
struct RRuleTests {
    @Test("daily defaults")
    func dailyDefaults() {
        let rule = RRule(frequency: .daily)
        #expect(rule.frequency == .daily)
        #expect(rule.interval == 1)
        #expect(rule.byWeekday.isEmpty)
        #expect(rule.byMonthDay == nil)
        #expect(rule.until == nil)
        #expect(rule.count == nil)
    }

    @Test("raw values use RFC codes")
    func rawValues() {
        #expect(RRule.Frequency.weekly.rawValue == "WEEKLY")
        #expect(RRule.Weekday.monday.rawValue == "MO")
        #expect(RRule.Weekday.sunday.rawValue == "SU")
    }

    @Test("Codable round-trips")
    func codable() throws {
        let rule = RRule(
            frequency: .weekly,
            interval: 2,
            byWeekday: [.tuesday, .thursday],
            until: Date(timeIntervalSince1970: 1_800_000_000),
            count: 10
        )
        let encoded = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(RRule.self, from: encoded)
        #expect(decoded == rule)
    }
}
