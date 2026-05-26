import Foundation
import NexusAI
import NexusCore
import Testing

@testable import TasksFeature

@Suite("HeroBriefService")
struct HeroBriefServiceTests {
    let now = ISO8601DateFormatter().date(from: "2026-05-04T08:30:00Z")!

    @Test("fallback renders grammatically correct overdue count")
    func fallbackOverdueSingular() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 1, today: 3, noDate: 1, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]1 przeterminowane zadanie[[/accent]]"))
    }

    @Test("fallback renders grammatically correct overdue paucal count")
    func fallbackOverduePaucal() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 2, today: 3, noDate: 1, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]2 przeterminowane zadania[[/accent]]"))
    }

    @Test("fallback renders grammatically correct overdue genitive plural count")
    func fallbackOverdueGenitivePlural() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 5, today: 3, noDate: 1, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]5 przeterminowanych zadań[[/accent]]"))
    }

    @Test("fallback renders grammatically correct awaiting singular count")
    func fallbackAwaitingSingular() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 3, noDate: 1, awaiting: 1)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]1 zadanie blokuje inne[[/accent]]"))
        #expect(!brief.contains("1 zadań"))
    }

    @Test("fallback renders grammatically correct awaiting paucal count")
    func fallbackAwaitingPaucal() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 3, noDate: 1, awaiting: 2)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]2 zadania blokują inne[[/accent]]"))
    }

    @Test("fallback renders grammatically correct awaiting genitive plural count")
    func fallbackAwaitingGenitivePlural() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 3, noDate: 1, awaiting: 5)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        #expect(brief.contains("[[accent]]5 zadań blokuje inne[[/accent]]"))
    }

    @Test("fallback renders grammatically correct no-date singular count")
    func fallbackNoDateSingular() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 0, noDate: 1, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: [], now: now)
        #expect(brief.contains("1 zadanie bez daty czeka."))
    }

    @Test("fallback renders grammatically correct no-date paucal count")
    func fallbackNoDatePaucal() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 0, noDate: 2, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: [], now: now)
        #expect(brief.contains("2 zadania bez daty czekają."))
    }

    @Test("fallback renders grammatically correct no-date genitive plural count")
    func fallbackNoDateGenitivePlural() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 0, noDate: 5, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: [], now: now)
        #expect(brief.contains("5 zadań bez daty czeka."))
    }

    @Test("fallback splits headline / subtitle by double newline")
    func fallbackSubtitle() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 1, noDate: 0, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["Foo"], now: now)
        let parts = brief.components(separatedBy: "\n\n")
        #expect(parts.count == 2)
        #expect(!parts[0].isEmpty)
        #expect(!parts[1].isEmpty)
    }

    @Test("fallback omits markers when no overdue and no today")
    func fallbackQuietDay() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 0, noDate: 5, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: [], now: now)
        #expect(!brief.contains("[[accent]]"))
    }

    @Test("fallback uses morning greeting between 5–12")
    func morningGreeting() async {
        let service = HeroBriefService(router: offlineRouter(), calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 3, today: 5, noDate: 2, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["x"], now: now)
        #expect(brief.contains("Dzień dobry"))
    }

    @Test("router success returns provider text")
    func successReturnsRouterText() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: "Cześć. Masz dziś 5 spotkań."
        )
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let service = HeroBriefService(router: router, calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 0, today: 5, noDate: 0, awaiting: 0)
        let brief = await service.brief(for: counts, firstTitles: ["sync"], now: now)
        #expect(brief == "Cześć. Masz dziś 5 spotkań.")
    }

    @Test("cache returns same value for repeated call within TTL")
    func cacheTTL() async {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            responseText: "first call"
        )
        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
        let service = HeroBriefService(router: router, calendar: gmtCalendar())
        let counts = HeroBriefService.Counts(overdue: 1, today: 1, noDate: 1, awaiting: 0)
        let first = await service.brief(for: counts, firstTitles: [], now: now)
        provider.responseText = "second call"
        let second = await service.brief(for: counts, firstTitles: [], now: now)
        #expect(first == second, "cached brief must not re-query within TTL")
    }

    private func gmtCalendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .gmt
        return cal
    }

    private func offlineRouter() -> AIRouter {
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            isAvailableOnThisPlatform: true,
            errorToThrow: .providerNotImplemented(.appleIntelligence)
        )
        return AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )
    }
}
