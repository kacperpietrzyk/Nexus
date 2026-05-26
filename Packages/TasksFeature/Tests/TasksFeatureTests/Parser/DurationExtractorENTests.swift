import Foundation
import Testing

@testable import TasksFeature

@Suite("DurationExtractor EN")
struct DurationExtractorENTests {
    private let startAt = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:30:00Z")!
    private let afternoonStartAt = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T14:00:00Z")!

    @Test(
        "DurationExtractor EN parses common duration phrases",
        arguments: [
            ("1h", 60),
            ("1.5h", 90),
            ("1 hour", 60),
            ("2 hours", 120),
            ("5 hours", 300),
            ("1.5 hours", 90),
            ("half hour", 30),
            ("half an hour", 30),
            ("an hour and a half", 90),
            ("1 hour and a half", 90),
            ("2 hours and a half", 150),
            ("1 hour and 30 minutes", 90),
            ("1 hour 30 minutes", 90),
            ("30 minutes", 30),
            ("30 min", 30),
            ("45min", 45),
            ("two hours", 120),
            ("three hours", 180),
            ("four hours", 240),
            ("five hours", 300),
            ("six hours", 360),
            ("five minutes", 5),
            ("ten minutes", 10),
            ("fifteen minutes", 15),
            ("twenty minutes", 20),
            ("thirty minutes", 30),
            ("forty five minutes", 45),
            ("for an hour", 60),
            ("for 30 minutes", 30),
            ("for 1.5 hours", 90),
        ] as [(String, Int)]
    )
    func parsesCommonENPhrases(input: String, expectedMinutes: Int) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en_US"), startAt: nil)

        #expect(match?.duration == TimeInterval(expectedMinutes * 60))
        #expect(consumedText(in: input, by: match) == input)
    }

    @Test(
        "DurationExtractor EN parses until-time when startAt exists",
        arguments: [
            ("until 16:00", 210),
            ("until 4pm", 210),
            ("until 4 PM", 210),
        ] as [(String, Int)]
    )
    func parsesUntilTimeWhenStartAtExists(input: String, expectedMinutes: Int) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: startAt)

        #expect(match?.duration == TimeInterval(expectedMinutes * 60))
        #expect(consumedText(in: input, by: match) == input)
    }

    @Test("DurationExtractor EN does not parse until-time without startAt anchor")
    func noAnchorReturnsNilForUntilTime() {
        let match = DurationExtractor.extract(from: "until 16:00", locale: Locale(identifier: "en"), startAt: nil)

        #expect(match == nil)
    }

    @Test("DurationExtractor EN returns nil when no duration phrase exists")
    func noPhraseReturnsNil() {
        let match = DurationExtractor.extract(from: "write report tomorrow", locale: Locale(identifier: "en"), startAt: nil)

        #expect(match == nil)
    }

    @Test("DurationExtractor EN returns the consumed range in the original string")
    func consumedRangeUsesOriginalStringIndices() throws {
        let input = "write report for 45min then"
        let match = try #require(DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: nil))

        #expect(match.duration == TimeInterval(45 * 60))
        #expect(match.consumed.count == 1)
        #expect(String(input[match.consumed[0]]) == "for 45min")
    }

    @Test("DurationExtractor EN is case-insensitive")
    func parserIsCaseInsensitive() {
        let input = "FOCUS FOR 2 HOURS"
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: nil)

        #expect(match?.duration == TimeInterval(2 * 60 * 60))
        #expect(consumedText(in: input, by: match) == "FOR 2 HOURS")
    }

    @Test("DurationExtractor EN parses embedded duration phrases")
    func parsesEmbeddedDuration() {
        let input = "review design 1 hour and 30 minutes #work"
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: nil)

        #expect(match?.duration == TimeInterval(90 * 60))
        #expect(consumedText(in: input, by: match) == "1 hour and 30 minutes")
    }

    @Test("DurationExtractor EN parses embedded until-time phrases")
    func parsesEmbeddedUntilTime() {
        let input = "work until 4pm then"
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: afternoonStartAt)

        #expect(match?.duration == TimeInterval(120 * 60))
        #expect(consumedText(in: input, by: match) == "until 4pm")
    }

    @Test(
        "DurationExtractor EN rejects zero durations",
        arguments: [
            "0h",
            "0 minutes",
            "0 hour",
        ]
    )
    func rejectsZero(input: String) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: startAt)

        #expect(match == nil)
    }

    @Test(
        "DurationExtractor EN rejects signed and huge numeric durations",
        arguments: [
            "-1h",
            "+1h",
            "-30 minutes",
            "-1.5h",
            "+1.5 hours",
            "-1,5h",
            "-1 hour and a half",
            "999999999999999999999999h",
        ]
    )
    func rejectsSignedAndHugeNumericDurations(input: String) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "en"), startAt: startAt)

        #expect(match == nil)
    }

    private func consumedText(in input: String, by match: DurationExtractor.Match?) -> String? {
        guard let match, let range = match.consumed.first else { return nil }
        return String(input[range])
    }
}
