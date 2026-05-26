import Foundation
import Testing

@testable import TasksFeature

@Suite("DurationExtractor PL")
struct DurationExtractorPLTests {
    private let startAt = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:30:00Z")!

    @Test(
        "DurationExtractor PL parses common duration phrases",
        arguments: [
            ("godzina i pół", 90),
            ("1 godzina i pół", 90),
            ("2 godziny i pół", 150),
            ("1 godzina i 30 minut", 90),
            ("2 godziny 15 minut", 135),
            ("1h", 60),
            ("2h", 120),
            ("1.5h", 90),
            ("1,5h", 90),
            ("1,5 godziny", 90),
            ("1 godzina", 60),
            ("2 godziny", 120),
            ("5 godzin", 300),
            ("30 minut", 30),
            ("30 min", 30),
            ("45min", 45),
            ("pół godziny", 30),
            ("dwie godziny", 120),
            ("trzy godziny", 180),
            ("cztery godziny", 240),
            ("pięć godzin", 300),
            ("sześć godzin", 360),
            ("pięć minut", 5),
            ("dziesięć minut", 10),
            ("piętnaście minut", 15),
            ("dwadzieścia minut", 20),
            ("trzydzieści minut", 30),
            ("czterdzieści pięć minut", 45),
        ] as [(String, Int)]
    )
    func parsesCommonPLPhrases(input: String, expectedMinutes: Int) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "pl_PL"), startAt: nil)

        #expect(match?.duration == TimeInterval(expectedMinutes * 60))
        #expect(consumedText(in: input, by: match) == input)
    }

    @Test(
        "DurationExtractor PL parses until-time when startAt exists",
        arguments: [
            ("do 16:00", 210),
            ("do 16", 210),
        ] as [(String, Int)]
    )
    func parsesUntilTimeWhenStartAtExists(input: String, expectedMinutes: Int) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "pl"), startAt: startAt)

        #expect(match?.duration == TimeInterval(expectedMinutes * 60))
        #expect(consumedText(in: input, by: match) == input)
    }

    @Test("DurationExtractor PL does not parse until-time without startAt anchor")
    func noAnchorReturnsNilForUntilTime() {
        let match = DurationExtractor.extract(from: "do 16:00", locale: Locale(identifier: "pl"), startAt: nil)

        #expect(match == nil)
    }

    @Test("DurationExtractor PL returns nil when no duration phrase exists")
    func noPhraseReturnsNil() {
        let match = DurationExtractor.extract(from: "napisz raport jutro", locale: Locale(identifier: "pl"), startAt: nil)

        #expect(match == nil)
    }

    @Test("DurationExtractor PL returns the consumed range in the original string")
    func consumedRangeUsesOriginalStringIndices() throws {
        let input = "napisz raport przez 45min potem"
        let match = try #require(DurationExtractor.extract(from: input, locale: Locale(identifier: "pl"), startAt: nil))

        #expect(match.duration == TimeInterval(45 * 60))
        #expect(match.consumed.count == 1)
        #expect(String(input[match.consumed[0]]) == "45min")
    }

    @Test("DurationExtractor PL is case-insensitive")
    func parserIsCaseInsensitive() {
        let match = DurationExtractor.extract(from: "FOCUS 2 GODZINY", locale: Locale(identifier: "pl"), startAt: nil)

        #expect(match?.duration == TimeInterval(2 * 60 * 60))
        #expect(consumedText(in: "FOCUS 2 GODZINY", by: match) == "2 GODZINY")
    }

    @Test("DurationExtractor PL parses embedded duration phrases")
    func parsesEmbeddedDuration() {
        let input = "review design 1 godzina i 30 minut #work"
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "pl"), startAt: nil)

        #expect(match?.duration == TimeInterval(90 * 60))
        #expect(consumedText(in: input, by: match) == "1 godzina i 30 minut")
    }

    @Test(
        "DurationExtractor PL rejects zero durations",
        arguments: [
            "0h",
            "0 minut",
            "0 godzina",
        ]
    )
    func rejectsZero(input: String) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "pl"), startAt: startAt)

        #expect(match == nil)
    }

    @Test(
        "DurationExtractor PL rejects signed and huge numeric durations",
        arguments: [
            "-1h",
            "+1h",
            "-30 minut",
            "-1.5h",
            "-1,5h",
            "-1 godzina i pół",
            "+1 godzina i pół",
            "999999999999999999999999h",
        ]
    )
    func rejectsSignedAndHugeNumericDurations(input: String) {
        let match = DurationExtractor.extract(from: input, locale: Locale(identifier: "pl"), startAt: startAt)

        #expect(match == nil)
    }

    private func consumedText(in input: String, by match: DurationExtractor.Match?) -> String? {
        guard let match, let range = match.consumed.first else { return nil }
        return String(input[range])
    }
}
