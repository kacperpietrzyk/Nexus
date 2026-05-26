import Foundation
import Testing

@testable import NexusCore

@Suite("RRuleParser")
struct RRuleParserTests {
    @Test("parses supported fields")
    func supportedFields() throws {
        let rule = try RRuleParser.parse(
            "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20261231T000000Z;COUNT=10"
        )
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 2)
        #expect(rule.byWeekday == [.monday, .wednesday])
        #expect(rule.until != nil)
        #expect(rule.count == 10)
    }

    @Test("parses monthly last day")
    func monthlyLastDay() throws {
        let rule = try RRuleParser.parse("FREQ=MONTHLY;BYMONTHDAY=-1")
        #expect(rule == RRule(frequency: .monthly, byMonthDay: -1))
    }

    @Test("rejects missing and unsupported fields")
    func rejectsInvalidInput() {
        #expect(throws: RRuleParseError.missingRequired("FREQ")) {
            _ = try RRuleParser.parse("INTERVAL=2")
        }
        #expect(throws: RRuleParseError.unsupportedToken("BYHOUR")) {
            _ = try RRuleParser.parse("FREQ=DAILY;BYHOUR=9")
        }
        #expect(throws: RRuleParseError.invalidFrequency("YEARLY")) {
            _ = try RRuleParser.parse("FREQ=YEARLY")
        }
    }

    @Test("rejects out-of-range BYMONTHDAY and invalid weekday")
    func rejectsInvalidValues() {
        #expect(throws: RRuleParseError.byMonthDayOutOfRange(32)) {
            _ = try RRuleParser.parse("FREQ=MONTHLY;BYMONTHDAY=32")
        }
        #expect(throws: RRuleParseError.invalidWeekday("XX")) {
            _ = try RRuleParser.parse("FREQ=WEEKLY;BYDAY=XX")
        }
    }
}
