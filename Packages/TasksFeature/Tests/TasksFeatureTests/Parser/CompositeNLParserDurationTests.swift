import Foundation
import NexusAI
import Testing

@testable import TasksFeature

@Suite("CompositeNLParser durations")
struct CompositeNLParserDurationTests {
    private let now = ISO8601DateFormatter.fixedNoon.date(from: "2026-05-04T12:00:00Z")!

    private func makeParser(fmJSON: String) -> (CompositeNLParser, FakeAIProvider) {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            isAvailableOnThisPlatform: true,
            responseText: fmJSON
        )
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let composite = CompositeNLParser(
            handcoded: HandcodedParser(),
            foundationModel: FoundationModelParser(router: router)
        )
        return (composite, provider)
    }

    @Test("handcoded path with duration produces endAt")
    func handcodedDurationProducesEndAt() async {
        let (composite, provider) = makeParser(fmJSON: #"{"title":"FM should not run"}"#)

        let result = await composite.parse(
            "meeting tomorrow 14:00 for 30 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "meeting")
        #expect(result.startAt == date(day: 5, hour: 14, minute: 0))
        #expect(result.endAt == date(day: 5, hour: 14, minute: 30))
        #expect(provider.generateCallCount == 0, "handcoded success must keep the zero-FM path")
    }

    @Test("FM cascade path with endAt preserves it")
    func fmEndAtIsPreserved() async {
        let json = """
            {
                "title": "Design review",
                "dueAt": null,
                "startAt": "2026-05-05T09:00:00Z",
                "endAt": "2026-05-05T11:00:00Z",
                "priority": 2,
                "tags": [],
                "recurrence": null
            }
            """
        let (composite, provider) = makeParser(fmJSON: json)

        let result = await composite.parse(
            "ambiguous design review for 30 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "Design review")
        #expect(result.startAt == date(day: 5, hour: 9, minute: 0))
        #expect(result.endAt == date(day: 5, hour: 11, minute: 0))
        #expect(result.priority == .medium)
        #expect(provider.generateCallCount == 1)
    }

    @Test("FM startAt plus original duration fills missing endAt")
    func fmMissingEndAtIsFilledFromOriginalDuration() async {
        let json = """
            {
                "title": "Design review",
                "dueAt": null,
                "startAt": "2026-05-05T09:00:00Z",
                "endAt": null,
                "priority": 2,
                "tags": [],
                "recurrence": null
            }
            """
        let (composite, provider) = makeParser(fmJSON: json)

        let result = await composite.parse(
            "ambiguous design review for 90 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "Design review")
        #expect(result.startAt == date(day: 5, hour: 9, minute: 0))
        #expect(result.endAt == date(day: 5, hour: 10, minute: 30))
        #expect(provider.generateCallCount == 1)
    }

    @Test("no duration phrase leaves FM endAt nil")
    func noDurationPhraseLeavesEndAtNil() async {
        let json = """
            {
                "title": "Design review",
                "dueAt": null,
                "startAt": "2026-05-05T09:00:00Z",
                "endAt": null,
                "priority": 2,
                "tags": [],
                "recurrence": null
            }
            """
        let (composite, _) = makeParser(fmJSON: json)

        let result = await composite.parse(
            "ambiguous design review",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.startAt == date(day: 5, hour: 9, minute: 0))
        #expect(result.endAt == nil)
    }

    @Test("without startAt duration cannot fill endAt")
    func durationWithoutStartAtCannotFillEndAt() async {
        let json = """
            {
                "title": "Design review",
                "dueAt": null,
                "startAt": null,
                "endAt": null,
                "priority": 2,
                "tags": [],
                "recurrence": null
            }
            """
        let (composite, _) = makeParser(fmJSON: json)

        let result = await composite.parse(
            "ambiguous design review for 90 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.startAt == nil)
        #expect(result.endAt == nil)
    }

    @Test("existing FM endAt is not overwritten by conflicting duration phrase")
    func existingFMEndAtIsNotOverwritten() async {
        let json = """
            {
                "title": "Design review",
                "dueAt": null,
                "startAt": "2026-05-05T09:00:00Z",
                "endAt": "2026-05-05T12:00:00Z",
                "priority": 2,
                "tags": [],
                "recurrence": null
            }
            """
        let (composite, _) = makeParser(fmJSON: json)

        let result = await composite.parse(
            "ambiguous design review for 90 minutes",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.startAt == date(day: 5, hour: 9, minute: 0))
        #expect(result.endAt == date(day: 5, hour: 12, minute: 0))
    }

    private func date(day: Int, hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour, minute: minute))
    }
}
