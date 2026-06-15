import Foundation
import NexusAI
import NexusCore

/// Generates the Today hero brief — 1-2 EN sentences. Uses the existing
/// `AIRouter` cascade (Apple Intelligence first per D5); falls back to a
/// deterministic template when no provider is available or the call errors.
/// Caches the last result for 30 minutes keyed on calendar-day + counts so
/// repeat focuses don't keep firing the LM.
///
/// The skill-backed path (Task 6) is injected via `skillPath` and
/// `readinessProbe` closures so no non-Sendable types live in the actor.
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
        // `meetings` feeds the skill-path prompt, so it must key the cache or a
        // changed meeting count returns a stale brief within the TTL.
        let meetings: Int
    }

    private let router: AIRouter
    private let calendar: Calendar
    private let ttl: TimeInterval
    private var cache: CacheEntry?

    // Skill-backed path: a closure that returns model text or throws.
    // Nil = router-only fallback path (original behaviour).
    private let skillPath: (@MainActor @Sendable (String, Date) async throws -> String)?
    // Readiness probe: returns .ready when the local model is loaded.
    private let readinessProbe: (@MainActor @Sendable () -> AssistantReadiness)?

    /// Original init: router-only fallback, no skill path.
    public init(
        router: AIRouter,
        calendar: Calendar = .current,
        ttl: TimeInterval = 30 * 60
    ) {
        self.router = router
        self.calendar = calendar
        self.ttl = ttl
        self.skillPath = nil
        self.readinessProbe = nil
    }

    /// Skill-backed init. `skillPath` receives `summaryNumbers` + `now` and
    /// returns model text. `readinessProbe` gates whether the skill path runs.
    /// Falls back to the deterministic template on not-ready or any error.
    public init(
        router: AIRouter,
        calendar: Calendar = .current,
        ttl: TimeInterval = 30 * 60,
        skillPath: @escaping @MainActor @Sendable (String, Date) async throws -> String,
        readinessProbe: @escaping @MainActor @Sendable () -> AssistantReadiness
    ) {
        self.router = router
        self.calendar = calendar
        self.ttl = ttl
        self.skillPath = skillPath
        self.readinessProbe = readinessProbe
    }

    public func brief(
        for counts: Counts,
        firstTitles: [String],
        now: Date,
        meetings: Int = 0
    ) async -> String {
        let key = CacheKey(
            dayBucket: calendar.component(.day, from: now),
            counts: counts,
            meetings: meetings
        )
        if let entry = cache, entry.key == key, now.timeIntervalSince(entry.timestamp) < ttl {
            return entry.value
        }
        let text = await query(counts: counts, firstTitles: firstTitles, meetings: meetings, now: now)
        cache = CacheEntry(key: key, value: text, timestamp: now)
        return text
    }

    private func query(
        counts: Counts,
        firstTitles: [String],
        meetings: Int,
        now: Date
    ) async -> String {
        if let skillPath, let readinessProbe {
            let readiness = await MainActor.run { readinessProbe() }
            if readiness == .ready {
                let summaryNumbers =
                    "overdue=\(counts.overdue), today=\(counts.today), noDate=\(counts.noDate), "
                    + "awaiting=\(counts.awaiting), meetings=\(meetings)"
                do {
                    return try await skillPath(summaryNumbers, now)
                } catch {
                    // fall through to deterministic template below
                }
            }
        }
        return await legacyQuery(counts: counts, firstTitles: firstTitles, now: now)
    }

    private func legacyQuery(counts: Counts, firstTitles: [String], now: Date) async -> String {
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
            Write a brief for the user in English, in two paragraphs:

            First paragraph (10-18 words): a narrative headline like \
            "Three things matter today - ...". Wrap the key actions in \
            [[accent]]...[[/accent]] (max 2). \
            Example: "Three things matter today - [[accent]]push the auth flow[[/accent]], \
            review Sam's PR."

            Second paragraph (10-25 words): a short sentence summarizing context or a \
            commitment. No markers.

            Separate paragraphs with a double newline.

            Numbers: \(counts.overdue) overdue, \(counts.today) today, \
            \(counts.noDate) with no date, \(counts.awaiting) blocking.
            Top titles:
            \(titles)
            """
    }

    private func fallback(counts: Counts, now: Date) -> String {
        let hour = calendar.component(.hour, from: now)
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good morning"
        case 12..<18: greeting = "Hi"
        case 18..<23: greeting = "Good evening"
        default: greeting = "Working late"
        }

        let headline: String
        if counts.overdue > 0 {
            let overduePhrase = "\(counts.overdue) overdue \(counts.overdue == 1 ? "task" : "tasks")"
            headline =
                "\(greeting). First [[accent]]\(overduePhrase)[[/accent]] — "
                + "then \(counts.today) today."
        } else if counts.awaiting > 0 {
            let awaitingPhrase = "\(counts.awaiting) \(counts.awaiting == 1 ? "task" : "tasks") blocking others"
            headline =
                "\(greeting). [[accent]]\(awaitingPhrase)[[/accent]] — move them before the rest."
        } else if counts.today > 0 {
            let todayPhrase = "\(counts.today) \(counts.today == 1 ? "task" : "tasks")"
            headline =
                "\(greeting). You have [[accent]]\(todayPhrase)[[/accent]] to close today."
        } else {
            let noDatePhrase = "\(counts.noDate) \(counts.noDate == 1 ? "task" : "tasks") with no date waiting"
            headline =
                "\(greeting). Quiet day — \(noDatePhrase)."
        }

        let subtitle = "Everything else has been quietly set aside."
        return "\(headline)\n\n\(subtitle)"
    }

}
