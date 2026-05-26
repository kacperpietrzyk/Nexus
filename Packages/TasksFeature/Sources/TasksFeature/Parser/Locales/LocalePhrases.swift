import Foundation
import NexusCore

/// Locale-specific phrase tables consumed by `Tokenizer` and `Resolver`. Tables
/// are pure data; values are the lowercased keyword the user typed mapped to
/// the parsed semantic. Adding a third locale = one extension file + one
/// branch in `table(for:)`.
public struct LocalePhrases: Sendable {
    public let languageCode: String

    /// "monday" / "poniedziałek" → `RRule.Weekday`.
    public let dayKeywords: [String: RRule.Weekday]

    /// "tomorrow" / "jutro" → days offset relative to `now`.
    public let relativeDays: [String: Int]

    /// "morning" / "rano" → seconds-into-day.
    public let timeOfDay: [String: TimeInterval]

    /// "every monday" / "co poniedziałek" → RRULE text.
    public let recurrenceKeywords: [String: String]

    /// "every day" / "co dzień" → RRULE text (no BYDAY).
    public let recurrenceFrequency: [String: String]

    /// "in N days" / "za N dni" tokens — used by `Tokenizer` to drive a regex.
    /// Key is the literal preposition, value is the unit's day-multiplier.
    public let relativeUnits: [String: Int]

    public init(
        languageCode: String,
        dayKeywords: [String: RRule.Weekday],
        relativeDays: [String: Int],
        timeOfDay: [String: TimeInterval],
        recurrenceKeywords: [String: String],
        recurrenceFrequency: [String: String],
        relativeUnits: [String: Int]
    ) {
        self.languageCode = languageCode
        self.dayKeywords = dayKeywords
        self.relativeDays = relativeDays
        self.timeOfDay = timeOfDay
        self.recurrenceKeywords = recurrenceKeywords
        self.recurrenceFrequency = recurrenceFrequency
        self.relativeUnits = relativeUnits
    }

    /// Pick a phrase table for the given locale. Falls back to English when
    /// the language is unsupported (Polish + English are the only locales in
    /// 1c per spec §8).
    public static func table(for locale: Locale) -> LocalePhrases {
        switch locale.language.languageCode?.identifier {
        case "pl": return .polish
        default: return .english
        }
    }

    /// Best-effort language detection from raw input — needed because users
    /// type Polish task notes on a Mac whose `Locale.current` is English.
    /// Looks for unambiguous Polish keywords (relative days, time-of-day,
    /// recurrence prepositions, units) before falling back to nil.
    public static func detectLocale(from input: String) -> Locale? {
        let lowered = input.lowercased()
        let polishMarkers: [String] = [
            "jutro", "dziś", "dzisiaj", "pojutrze", "wczoraj",
            "rano", "wieczorem", "w nocy", "w południe",
            "codziennie", "co dzień", "co tydzień", "co miesiąc",
            "za godzinę", "za dzień", "za tydzień",
            "termin", "najpóźniej", "do dnia", "do końca",
            "poniedziałek", "wtorek", "środa", "środę", "czwartek",
            "piątek", "sobota", "sobotę", "niedziela", "niedzielę",
            "spotkanie", "rozmowa", "trening", "obiad", "kolacja",
        ]
        for marker in polishMarkers
        where lowered.range(of: marker, options: [.diacriticInsensitive]) != nil {
            return Locale(identifier: "pl_PL")
        }
        return nil
    }
}
