import Foundation

/// Static prompt template for the foundation-model JSON contract. Locale is
/// surfaced explicitly so the LM emits dates in the user's calendar (no
/// auto-translate of phrases), and `now` is encoded as an ISO8601 anchor so
/// "tomorrow" / "jutro" resolutions are deterministic across LM calls.
internal enum FMPromptTemplate {
    static func make(input: String, now: Date, locale: Locale) -> String {
        let nowISO: String = ISO8601DateFormatter.fixedFM.string(from: now)
        let lang = locale.language.languageCode?.identifier ?? "en"

        return """
            You are a task input parser. Parse the user's natural-language task entry into \
            a single JSON object matching the schema below. \
            Do NOT include any text outside the JSON object — no prose preamble, no markdown fences.

            Schema:
            {
              "title": string,                    // task title with date/priority/tag tokens removed
              "dueAt": string | null,             // ISO8601 UTC, e.g. "2026-05-05T00:00:00Z"
              "startAt": string | null,           // ISO8601 UTC if a time-of-day is implied
              "endAt": string | null,             // ISO8601 UTC if duration/end time is implied
              "deadlineAt": string | null,        // ISO8601 UTC for deadline/by/termin phrases
              "priority": integer | null,         // 0=none, 1=low, 2=medium, 3=high
              "tags": string[] | null,            // lowercased, no leading '#'
              "project": string | null,           // project name if the user wrote an @token, no leading '@'
              "recurrence": string | null         // RRULE, e.g. "FREQ=WEEKLY;BYDAY=MO"; "every!"/"co!" add ";ANCHOR=COMPLETION"
            }

            Anchors:
            - now: \(nowISO)
            - locale: \(lang)

            User input: \(input)

            JSON:
            """
    }
}

// nonisolated(unsafe) required: ISO8601DateFormatter is a class (reference type);
// Swift 6 strict concurrency treats stored static lets on class types as
// potentially mutable shared state across actors. The nonisolated(unsafe)
// annotation opts out of the actor-isolation check — safe here because the
// formatter is constructed once and its formatOptions / timeZone are never
// mutated after init.
extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fixedFM: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
