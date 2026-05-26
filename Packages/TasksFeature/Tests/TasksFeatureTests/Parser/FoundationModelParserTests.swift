import Foundation
import NexusAI
import NexusCore
import Testing

@testable import TasksFeature

@Suite("FoundationModelParser")
struct FoundationModelParserTests {
    let now = ISO8601DateFormatter.fixedFM.date(from: "2026-05-04T12:00:00Z")!

    private func makeRouter(provider: FakeAIProvider) -> AIRouter {
        AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
    }

    @Test("decodes valid JSON response into ParseResult")
    func happyPath() async {
        let json =
            """
            {
              "title": "Buy milk",
              "dueAt": "2026-05-05T00:00:00Z",
              "deadlineAt": "2026-05-08T00:00:00Z",
              "priority": 2,
              "tags": ["shopping"],
              "recurrence": null
            }
            """
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            isAvailableOnThisPlatform: true,
            responseText: json
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        let result = await parser.parse(
            "kup mleko jutro", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "Buy milk")
        #expect(result.dueAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T00:00:00Z"))
        #expect(result.deadlineAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-08T00:00:00Z"))
        #expect(result.priority == .medium)
        #expect(result.tags == ["shopping"])
        #expect(result.recurrence == nil)
        #expect(result.confidence == 0.8)
    }

    @Test("strips prose preamble before decoding")
    func proseStripped() async {
        let raw = #"Sure, here is the parse: {"title":"Buy milk"} hope that helps!"#
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: raw
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        let result = await parser.parse("kup mleko", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "Buy milk")
    }

    @Test("router error falls back to title-only result")
    func routerErrorFallback() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            errorToThrow: .providerNotImplemented(.appleIntelligence)
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        let result = await parser.parse("kup mleko", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kup mleko")
        #expect(result.dueAt == nil)
        #expect(result.confidence == 0.0)
    }

    @Test("malformed JSON falls back to title-only result")
    func malformedFallback() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: "no json here"
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        let result = await parser.parse("kup mleko", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kup mleko")
    }

    @Test("invokes provider exactly once per parse")
    func singleInvocation() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: #"{"title":"x"}"#
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        _ = await parser.parse("input", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(provider.generateCallCount == 1)
    }

    @Test("strips leading # from FM-emitted tags so output matches handcoded parser")
    func tagNormalizationMatchesHandcoded() async {
        let input = "buy bread #Shopping #work/projectA"
        let handcodedTags = await HandcodedParser().parse(
            input,
            locale: Locale(identifier: "en"),
            now: now
        ).tags

        let json = ##"{"title":"buy bread","tags":["#Shopping","#work/projectA"]}"##
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: json
        )
        let parser = FoundationModelParser(router: makeRouter(provider: provider))
        let fmResult = await parser.parse(input, locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)

        #expect(handcodedTags == ["shopping", "work/projecta"])
        #expect(fmResult.tags == handcodedTags)
    }
}
