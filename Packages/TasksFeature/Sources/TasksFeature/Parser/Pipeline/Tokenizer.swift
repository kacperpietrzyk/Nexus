import Foundation
import NexusCore

internal struct Tokenizer: Sendable {
    func tokenize(_ input: String, locale: LocalePhrases) -> [Token] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var tokens: [Token] = []
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0

        while index < words.count {
            if let (token, consumed) = matchRecurrencePhrase(words, at: index, locale: locale) {
                tokens.append(token)
                index += consumed
                continue
            }
            if let (token, consumed) = matchRelativePhrase(words, at: index, locale: locale) {
                tokens.append(token)
                index += consumed
                continue
            }
            if let (token, consumed) = matchTimeOfDayPhrase(words, at: index, locale: locale) {
                tokens.append(token)
                index += consumed
                continue
            }
            tokens.append(classify(word: words[index], locale: locale))
            index += 1
        }
        return tokens
    }

    private func matchRecurrencePhrase(
        _ words: [String],
        at index: Int,
        locale: LocalePhrases
    ) -> (Token, Int)? {
        // Todoist "every!" semantics (T1): a trailing "!" on the first keyword
        // word ("every!", "co!", "daily!", "codziennie!") marks the rule as
        // completion-anchored — the next occurrence advances from the
        // completion date, not the due date. The marker is stripped before the
        // table lookup and re-encoded as the `ANCHOR=COMPLETION` RRULE token,
        // so both locale tables stay untouched.
        let (firstWord, completionAnchored) = strippingCompletionMarker(words[index].lowercased())
        // Two-word recurrence keyword (e.g. "co poniedziałek", "every monday")
        if index + 1 < words.count {
            let twoWord = "\(firstWord) \(words[index + 1].lowercased())"
            if let rrule = locale.recurrenceKeywords[twoWord] {
                return (.recurrence(rrule: anchored(rrule, completionAnchored), confidence: 0.95), 2)
            }
            if let rrule = locale.recurrenceFrequency[twoWord] {
                return (.recurrence(rrule: anchored(rrule, completionAnchored), confidence: 0.95), 2)
            }
        }
        // Single-word frequency (e.g. "daily", "codziennie")
        if let rrule = locale.recurrenceFrequency[firstWord] {
            return (.recurrence(rrule: anchored(rrule, completionAnchored), confidence: 0.9), 1)
        }
        return nil
    }

    private func strippingCompletionMarker(_ word: String) -> (word: String, hasMarker: Bool) {
        guard word.count > 1, word.hasSuffix("!") else { return (word, false) }
        return (String(word.dropLast()), true)
    }

    private func anchored(_ rrule: String, _ completionAnchored: Bool) -> String {
        guard completionAnchored else { return rrule }
        return RRuleAnchorToken.applying(completionAnchor: true, to: rrule)
    }

    private func matchTimeOfDayPhrase(
        _ words: [String],
        at index: Int,
        locale: LocalePhrases
    ) -> (Token, Int)? {
        // Two-word time-of-day phrase (e.g. "po południu", "w południe", "w nocy").
        // Mirrors `matchRecurrencePhrase`; single-word forms still flow through
        // `classify` below.
        guard index + 1 < words.count else { return nil }
        let twoWord = "\(words[index].lowercased()) \(words[index + 1].lowercased())"
        if let secs = locale.timeOfDay[twoWord] {
            return (.timeOfDay(secondsIntoDay: secs, confidence: 0.7), 2)
        }
        return nil
    }

    private func matchRelativePhrase(
        _ words: [String],
        at index: Int,
        locale: LocalePhrases
    ) -> (Token, Int)? {
        let preposition = locale.languageCode == "pl" ? "za" : "in"
        guard index < words.count, words[index].lowercased() == preposition else { return nil }

        // "za 3 dni" / "in 5 days" — 3 words
        if index + 2 < words.count, let amount = Int(words[index + 1]), let unit = locale.relativeUnits[words[index + 2].lowercased()] {
            return (.relativePhrase(amount: amount, unitDays: unit, confidence: 0.9), 3)
        }

        // "za tydzień" / "in week" — 2 words (implicit amount = 1)
        if index + 1 < words.count, let unit = locale.relativeUnits[words[index + 1].lowercased()] {
            return (.relativePhrase(amount: 1, unitDays: unit, confidence: 0.85), 2)
        }

        return nil
    }

    private func classify(word: String, locale: LocalePhrases) -> Token {
        if word.hasPrefix("#"), word.count > 1, word.range(of: #"^#[A-Za-z0-9_/-]+$"#, options: .regularExpression) != nil {
            let body = String(word.dropFirst()).lowercased()
            return .tag(body, confidence: 0.95)
        }
        if word.range(of: #"^![1-4]$"#, options: .regularExpression) != nil, let digit = Int(word.dropFirst()) {
            let priority: TaskPriority
            switch digit {
            case 1: priority = .high
            case 2: priority = .medium
            case 3: priority = .low
            default: priority = TaskPriority.none
            }
            return .priority(priority, confidence: 0.95)
        }
        let lower = word.lowercased()
        if let secs = locale.timeOfDay[lower] {
            return .timeOfDay(secondsIntoDay: secs, confidence: 0.7)
        }
        if let day = locale.dayKeywords[lower] {
            return .dayKeyword(day, confidence: 0.85)
        }
        if let offset = locale.relativeDays[lower] {
            return .relativeDay(offset: offset, confidence: 0.9)
        }
        if word.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return .dateLiteral(word, confidence: 0.95)
        }
        if word.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil {
            return .dateLiteral(word, confidence: 0.95)
        }
        if word.range(of: #"^\d{1,2}\.\d{1,2}$"#, options: .regularExpression) != nil {
            return .dateLiteral(word, confidence: 0.85)
        }
        if word.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return .dateLiteral(word, confidence: 0.9)
        }
        return .residual(word)
    }
}
