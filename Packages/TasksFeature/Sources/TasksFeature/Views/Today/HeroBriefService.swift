import Foundation
import NexusAI
import NexusCore

/// Generates the Today hero brief — 1-2 PL sentences. Uses the existing
/// `AIRouter` cascade (Apple Intelligence first per D5); falls back to a
/// deterministic template when no provider is available or the call errors.
/// Caches the last result for 30 minutes keyed on calendar-day + counts so
/// repeat focuses don't keep firing the LM.
public actor HeroBriefService {

    public struct Counts: Hashable, Sendable {
        public let overdue: Int
        public let today: Int
        public let noDate: Int
        public let awaiting: Int
        public init(overdue: Int, today: Int, noDate: Int, awaiting: Int) {
            self.overdue = overdue
            self.today = today
            self.noDate = noDate
            self.awaiting = awaiting
        }
    }

    private struct CacheEntry {
        let key: CacheKey
        let value: String
        let timestamp: Date
    }

    private struct CacheKey: Hashable {
        let dayBucket: Int
        let counts: Counts
    }

    private let router: AIRouter
    private let calendar: Calendar
    private let ttl: TimeInterval
    private var cache: CacheEntry?

    public init(
        router: AIRouter,
        calendar: Calendar = .current,
        ttl: TimeInterval = 30 * 60
    ) {
        self.router = router
        self.calendar = calendar
        self.ttl = ttl
    }

    public func brief(
        for counts: Counts,
        firstTitles: [String],
        now: Date
    ) async -> String {
        let key = CacheKey(dayBucket: calendar.component(.day, from: now), counts: counts)
        if let entry = cache, entry.key == key, now.timeIntervalSince(entry.timestamp) < ttl {
            return entry.value
        }
        let text = await query(counts: counts, firstTitles: firstTitles, now: now)
        cache = CacheEntry(key: key, value: text, timestamp: now)
        return text
    }

    private func query(counts: Counts, firstTitles: [String], now: Date) async -> String {
        let prompt = makePrompt(counts: counts, firstTitles: firstTitles)
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: .offlineOnly,
            cost: .free,
            providerPreference: .auto
        )
        do {
            let response = try await router.route(request)
            let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallback(counts: counts, now: now) : trimmed
        } catch {
            return fallback(counts: counts, now: now)
        }
    }

    private func makePrompt(counts: Counts, firstTitles: [String]) -> String {
        let titles = firstTitles.prefix(3).map { "- \($0)" }.joined(separator: "\n")
        return """
            Napisz brief dla użytkownika po polsku w dwóch akapitach:

            Pierwszy akapit (10–18 słów): nagłówek narracyjny w stylu \
            "Trzy rzeczy mają znaczenie dziś — ...". Wyróżnij kluczowe akcje \
            owinając je w [[accent]]...[[/accent]] (maks. 2 wyróżnienia). \
            Przykład: "Trzy rzeczy mają znaczenie dziś — [[accent]]wypchnij auth flow[[/accent]], \
            review PR Sama."

            Drugi akapit (10–25 słów): krótkie zdanie podsumowujące kontekst lub \
            zobowiązanie. Bez znaczników.

            Oddziel akapity podwójnym znakiem nowej linii.

            Liczby: \(counts.overdue) przeterminowanych, \(counts.today) na dziś, \
            \(counts.noDate) bez daty, \(counts.awaiting) blokujących.
            Pierwsze tytuły:
            \(titles)
            """
    }

    private func fallback(counts: Counts, now: Date) -> String {
        let hour = calendar.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Dzień dobry"
        case 12..<18: greeting = "Cześć"
        case 18..<23: greeting = "Dobry wieczór"
        default: greeting = "Późno"
        }

        let headline: String
        if counts.overdue > 0 {
            headline =
                "\(greeting). Najpierw [[accent]]\(PolishPlurals.overdueTasksPhrase(counts.overdue))[[/accent]] — "
                + "potem \(counts.today) na dziś."
        } else if counts.awaiting > 0 {
            headline =
                "\(greeting). [[accent]]\(PolishPlurals.awaitingBlocksPhrase(counts.awaiting))[[/accent]] — rusz je przed resztą."
        } else if counts.today > 0 {
            headline =
                "\(greeting). Dziś masz [[accent]]\(PolishPlurals.countWithTasks(counts.today))[[/accent]] do zamknięcia."
        } else {
            headline =
                "\(greeting). Spokojny dzień — \(PolishPlurals.noDateWaitingPhrase(counts.noDate))."
        }

        let subtitle = "Wszystko inne zostało po cichu odłożone."
        return "\(headline)\n\n\(subtitle)"
    }

}
