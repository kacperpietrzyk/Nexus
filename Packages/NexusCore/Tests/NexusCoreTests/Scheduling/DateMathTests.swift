import Foundation
import Testing
@testable import NexusCore

@Suite struct DateMathTests {
    // Deterministic fake so we don't depend on the real parser here.
    struct FixedExtractor: DateExtracting {
        let result: Date?
        func date(from hint: String, now: Date, locale: Locale) async -> Date? { result }
    }

    @Test func startOfDayUsesProvidedCalendar() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let math = DateMath(calendar: cal)
        let noon = Date(timeIntervalSince1970: 1_800_000_000) // arbitrary
        let sod = math.startOfDay(noon)
        #expect(cal.component(.hour, from: sod) == 0)
        #expect(cal.component(.minute, from: sod) == 0)
    }

    @Test func nextNDaysProducesDistinctConsecutiveStartOfDays() {
        let math = DateMath(calendar: .current)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let days = math.nextDays(3, from: now)
        #expect(days.count == 3)
        #expect(Set(days).count == 3)
    }

    @Test func resolveDelegatesToExtractor() async {
        let target = Date(timeIntervalSince1970: 1_800_100_000)
        let math = DateMath(calendar: .current, extractor: FixedExtractor(result: target))
        let resolved = await math.resolve("piątek", now: .now, locale: Locale(identifier: "pl_PL"))
        #expect(resolved == target)
    }
}
