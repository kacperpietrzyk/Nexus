import Foundation
import NexusAI
import NexusCore
import Testing

@testable import TasksFeature

@Suite("CompositeNLParser")
struct CompositeNLParserTests {
    let now = ISO8601DateFormatter.fixedFM.date(from: "2026-05-04T12:00:00Z")!

    private func makeParser(fmJSON: String) -> (CompositeNLParser, FakeAIProvider) {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
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

    @Test("happy path skips FM when handcoded finds dueAt")
    func skipsFMOnHandcodedHit() async {
        let (composite, provider) = makeParser(fmJSON: #"{"title":"FM"}"#)
        let result = await composite.parse(
            "buy milk tomorrow !2", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "buy milk")
        #expect(result.dueAt != nil)
        #expect(result.priority == .medium)
        #expect(provider.generateCallCount == 0, "FM must not be called when handcoded succeeds")
    }

    @Test("deadline pre-pass skips FM and preserves separate due date")
    func deadlineSkipsFM() async {
        let (composite, provider) = makeParser(fmJSON: #"{"title":"FM"}"#)
        let result = await composite.parse(
            "meeting tomorrow by friday",
            locale: Locale(identifier: "en"),
            now: now,
            calendar: ParserCalendar.deterministic
        )

        #expect(result.title == "meeting")
        #expect(result.dueAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T00:00:00Z"))
        #expect(result.deadlineAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-08T00:00:00Z"))
        #expect(provider.generateCallCount == 0, "FM must not be called when deadline pre-pass succeeds")
    }

    @Test("falls through to FM when handcoded has low confidence and no date")
    func cascadesToFM() async {
        let json =
            #"{"title":"go shopping","dueAt":"2026-05-05T00:00:00Z","priority":null,"tags":[],"recurrence":null}"#
        let (composite, provider) = makeParser(fmJSON: json)
        let result = await composite.parse(
            "po obiedzie kupić chleb", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "go shopping")
        #expect(result.dueAt == ISO8601DateFormatter.fixedFM.date(from: "2026-05-05T00:00:00Z"))
        #expect(
            provider.generateCallCount == 1,
            "FM must be called when handcoded has no date and low confidence")
    }

    @Test("FM with no structure falls back to handcoded title-only")
    func fmEmptyFallsBack() async {
        let json = #"{"title":"only title"}"#
        let (composite, provider) = makeParser(fmJSON: json)
        let result = await composite.parse("kup chleb", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kup chleb", "no structure from FM → keep handcoded title")
        #expect(provider.generateCallCount == 1)
    }

    @Test("recurrence-only handcoded result skips FM")
    func recurrenceSkipsFM() async {
        let (composite, provider) = makeParser(fmJSON: #"{"title":"FM"}"#)
        let result = await composite.parse(
            "water plants daily", locale: Locale(identifier: "en"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.recurrence == "FREQ=DAILY")
        #expect(provider.generateCallCount == 0)
    }

    @Test("router error during FM augmentation preserves handcoded result")
    func fmErrorPreservesHandcoded() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            errorToThrow: .providerNotImplemented(.appleIntelligence)
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
        let result = await composite.parse("kup chleb", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "kup chleb")
        #expect(result.dueAt == nil)
    }

    @Test("priority-only handcoded with high confidence skips FM despite no date/recurrence")
    func confidenceCutoffSkipsFM() async {
        // Input "!1 important task" produces a priority token at confidence 0.95
        // (Tokenizer.classify line 87) and no dueAt / recurrence. The cascade
        // condition (`dueAt == nil && recurrence == nil && confidence < 0.7`)
        // is false because confidence >= 0.7, so FM must not be invoked. This
        // pins the confidence-only branch — the existing skipsFMOnHandcodedHit
        // exercises the dueAt-only branch.
        let (composite, provider) = makeParser(fmJSON: #"{"title":"FM-should-not-run"}"#)
        let result = await composite.parse(
            "!1 important task",
            locale: Locale(identifier: "en"),
            now: now
        )
        #expect(result.priority == .high)
        #expect(result.dueAt == nil)
        #expect(result.recurrence == nil)
        #expect(
            provider.generateCallCount == 0,
            "FM must skip when handcoded confidence >= cutoff even without date/recurrence"
        )
    }
}
