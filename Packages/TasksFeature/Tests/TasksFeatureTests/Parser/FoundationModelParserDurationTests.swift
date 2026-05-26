import Foundation
import NexusAI
import Testing

@testable import TasksFeature

@Suite("FoundationModelParser durations")
struct FoundationModelParserDurationTests {
    let now = ISO8601DateFormatter.fixedFM.date(from: "2026-05-04T12:00:00Z")!

    private func makeRouter(responseText: String) -> AIRouter {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            isAvailableOnThisPlatform: true,
            responseText: responseText
        )
        return AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
    }

    @Test("decodes valid ISO8601 endAt and preserves duration relation to startAt")
    func decodesValidEndAtWithDuration() async throws {
        let json = """
            {
                "title": "Design review",
                "dueAt": "2026-05-05T00:00:00Z",
                "startAt": "2026-05-05T09:00:00Z",
                "endAt": "2026-05-05T10:30:00Z",
                "priority": null,
                "tags": null,
                "recurrence": null
            }
            """
        let parser = FoundationModelParser(router: makeRouter(responseText: json))

        let result = await parser.parse(
            "design review tomorrow 9 for 90 minutes", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        let startAt = try #require(result.startAt)
        let endAt = try #require(result.endAt)
        #expect(endAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T10:30:00Z"))
        #expect(endAt.timeIntervalSince(startAt) == 90 * 60)
    }

    @Test("null endAt maps to nil")
    func nullEndAtMapsToNil() async {
        let json = #"{"title":"Buy milk","dueAt":null,"startAt":"2026-05-05T09:00:00Z","endAt":null}"#
        let parser = FoundationModelParser(router: makeRouter(responseText: json))

        let result = await parser.parse("buy milk at 9", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.startAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T09:00:00Z"))
        #expect(result.endAt == nil)
    }

    @Test("missing endAt key maps to nil")
    func missingEndAtMapsToNil() async {
        let json = #"{"title":"Buy milk","dueAt":null,"startAt":"2026-05-05T09:00:00Z"}"#
        let parser = FoundationModelParser(router: makeRouter(responseText: json))

        let result = await parser.parse("buy milk at 9", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.startAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T09:00:00Z"))
        #expect(result.endAt == nil)
    }

    @Test("malformed endAt string maps to nil")
    func malformedEndAtMapsToNil() async {
        let json = #"{"title":"Buy milk","startAt":"2026-05-05T09:00:00Z","endAt":"tomorrow evening"}"#
        let parser = FoundationModelParser(router: makeRouter(responseText: json))

        let result = await parser.parse(
            "buy milk at 9 until tomorrow evening", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.startAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T09:00:00Z"))
        #expect(result.endAt == nil)
    }

    @Test("endAt is preserved on success path")
    func endAtPreservedOnSuccessPath() async {
        let json = """
            Here is the JSON:
            {
                "title": "Workshop",
                "dueAt": null,
                "startAt": "2026-05-05T13:00:00Z",
                "endAt": "2026-05-05T15:00:00Z",
                "priority": 3,
                "tags": ["planning"],
                "recurrence": null
            }
            """
        let parser = FoundationModelParser(router: makeRouter(responseText: json))

        let result = await parser.parse(
            "workshop tomorrow 13-15 #planning high", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(result.title == "Workshop")
        #expect(result.startAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T13:00:00Z"))
        #expect(result.endAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T15:00:00Z"))
        #expect(result.priority == .high)
        #expect(result.tags == ["planning"])
        #expect(result.confidence == 0.8)
    }
}
