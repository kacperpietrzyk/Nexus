import Foundation

/// Deterministic locale-driven parser. Three-stage pipeline:
/// `Tokenizer` → `Resolver` → `Composer`. Carries no state between calls
/// (struct, not actor) — caller is free to share one instance.
public struct HandcodedParser: NLParser {
    private let tokenizer: Tokenizer
    private let resolver: Resolver
    private let composer: Composer
    private let deadlineExtractor: DeadlineExtractor

    public init() {
        self.tokenizer = Tokenizer()
        self.resolver = Resolver()
        self.composer = Composer()
        self.deadlineExtractor = DeadlineExtractor()
    }

    public func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult {
        let table = LocalePhrases.table(for: locale)
        let deadline = deadlineExtractor.extract(from: input, locale: locale, now: now, calendar: calendar)
        let workingInput = deadline.strippedInput
        let tokens = tokenizer.tokenize(workingInput, locale: table)
        let resolved = resolver.resolve(tokens, locale: table, now: now, calendar: calendar)
        var result = composer.compose(resolved, input: workingInput, now: now, calendar: calendar)
        result.deadlineAt = deadline.deadlineAt

        guard
            let duration = durationMatchAndStartAt(
                from: workingInput,
                result: result,
                locale: locale,
                now: now,
                calendar: calendar
            )
        else {
            if let endpointOnly = endpointOnlyUntilPhrase(from: workingInput, locale: locale) {
                result.startAt = nil
                result.endAt = nil
                result.title = titleByRemovingConsumedPhrases(
                    from: result.title,
                    context: ConsumedPhraseRemovalContext(
                        match: endpointOnly,
                        input: workingInput,
                        locale: table,
                        now: now,
                        calendar: calendar
                    )
                )
            }
            return result
        }

        result.startAt = duration.startAt
        result.endAt = duration.startAt.addingTimeInterval(duration.match.duration)
        result.title = titleByRemovingConsumedPhrases(
            from: result.title,
            context: ConsumedPhraseRemovalContext(
                match: duration.match,
                input: workingInput,
                locale: table,
                now: now,
                calendar: calendar
            )
        )
        return result
    }

    private func durationMatchAndStartAt(
        from input: String,
        result: ParseResult,
        locale: Locale,
        now: Date,
        calendar: Calendar
    ) -> (match: DurationExtractor.Match, startAt: Date)? {
        if let startAt = result.startAt {
            if let match = DurationExtractor.extract(from: input, locale: locale, startAt: startAt) {
                return (match, startAt)
            }
        }

        guard
            let fallbackStartAt = firstClockTimeBeforeUntilPhrase(
                in: input,
                locale: locale,
                baseDate: result.dueAt ?? calendar.startOfDay(for: now),
                calendar: calendar
            ),
            let match = DurationExtractor.extract(from: input, locale: locale, startAt: fallbackStartAt)
        else { return nil }

        return (match, fallbackStartAt)
    }

    private func endpointOnlyUntilPhrase(from input: String, locale: Locale) -> DurationExtractor.Match? {
        guard
            let match = firstMatch(in: input, pattern: untilPattern(for: locale)),
            firstClockTimeBefore(range: match.range, in: input) == nil
        else { return nil }

        return DurationExtractor.Match(duration: 0, consumed: [match.range])
    }

    private struct ConsumedPhraseRemovalContext {
        let match: DurationExtractor.Match
        let input: String
        let locale: LocalePhrases
        let now: Date
        let calendar: Calendar
    }

    private func titleByRemovingConsumedPhrases(
        from title: String,
        context: ConsumedPhraseRemovalContext
    ) -> String {
        var stripped = title
        for range in context.match.consumed {
            let consumed = String(context.input[range])
            let residual = residualTitle(
                for: consumed,
                locale: context.locale,
                now: context.now,
                calendar: context.calendar
            )
            stripped = removingPhrase(consumed, from: stripped, occurrence: .first)
            stripped = removingPhrase(residual, from: stripped, occurrence: .last)
        }
        return normalizedWhitespace(stripped)
    }

    private func residualTitle(for input: String, locale: LocalePhrases, now: Date, calendar: Calendar) -> String {
        let tokens = tokenizer.tokenize(input, locale: locale)
        let resolved = resolver.resolve(tokens, locale: locale, now: now, calendar: calendar)
        return composer.compose(resolved, input: input, now: now, calendar: calendar).title
    }

    private func removingPhrase(_ phrase: String, from title: String, occurrence: PhraseOccurrence) -> String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return title }

        var updated = title
        var searchStart = updated.startIndex
        var lastMatchedRange: Range<String.Index>?
        while let range = updated.range(
            of: trimmed,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<updated.endIndex
        ) {
            let isBounded =
                isPhraseBoundary(range.lowerBound, in: updated, before: true)
                && isPhraseBoundary(range.upperBound, in: updated, before: false)
            if isBounded {
                switch occurrence {
                case .first:
                    updated.removeSubrange(range)
                    return updated
                case .last:
                    lastMatchedRange = range
                    searchStart = range.upperBound
                }
            } else {
                searchStart = range.upperBound
            }
        }
        if let lastMatchedRange {
            updated.removeSubrange(lastMatchedRange)
        }
        return updated
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func firstClockTimeBeforeUntilPhrase(
        in input: String,
        locale: Locale,
        baseDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let untilRange = firstMatchRange(in: input, pattern: untilPattern(for: locale)),
            let time = firstClockTimeBefore(range: untilRange, in: input)
        else { return nil }

        let (hour, minute) = time

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func untilPattern(for locale: Locale) -> String {
        if locale.language.languageCode?.identifier == "pl" {
            return #"(?<![\p{L}\p{N}])do\s+([01]?\d|2[0-3])(?::([0-5]\d))?(?![\p{L}\p{N}])"#
        }
        return #"(?<![\p{L}\p{N}])until\s+([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?(?![\p{L}\p{N}])"#
    }

    private func firstMatchRange(in input: String, pattern: String) -> Range<String.Index>? {
        allMatches(in: input, pattern: pattern).first?.range
    }

    private func firstMatch(in input: String, pattern: String) -> LocalRegexMatch? {
        allMatches(in: input, pattern: pattern).first
    }

    private func firstClockTimeBefore(range: Range<String.Index>, in input: String) -> (hour: Int, minute: Int)? {
        let prefix = String(input[..<range.lowerBound])
        let timePattern = #"(?<![\p{L}\p{N}])([01]?\d|2[0-3]):([0-5]\d)(?![\p{L}\p{N}])"#
        guard
            let match = allMatches(in: prefix, pattern: timePattern).last,
            let hourText = match.text(at: 1, in: prefix),
            let minuteText = match.text(at: 2, in: prefix),
            let hour = Int(hourText),
            let minute = Int(minuteText)
        else { return nil }

        return (hour, minute)
    }

    private func allMatches(in input: String, pattern: String) -> [LocalRegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { result in
            guard let range = Range(result.range, in: input) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> Range<String.Index>? in
                let groupRange = result.range(at: index)
                guard groupRange.location != NSNotFound else { return nil }
                return Range(groupRange, in: input)
            }
            return LocalRegexMatch(range: range, groups: groups)
        }
    }

    private func isPhraseBoundary(_ index: String.Index, in value: String, before: Bool) -> Bool {
        if before {
            guard index > value.startIndex else { return true }
            return !isWordCharacter(value[value.index(before: index)])
        }
        guard index < value.endIndex else { return true }
        return !isWordCharacter(value[index])
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}

private struct LocalRegexMatch {
    let range: Range<String.Index>
    let groups: [Range<String.Index>?]

    func text(at index: Int, in input: String) -> String? {
        guard groups.indices.contains(index), let range = groups[index] else { return nil }
        return String(input[range])
    }
}

private enum PhraseOccurrence {
    case first
    case last
}
