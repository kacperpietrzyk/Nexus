import Foundation

internal struct DeadlineExtractor: Sendable {
    struct Extraction: Sendable, Equatable {
        let strippedInput: String
        let deadlineAt: Date?
    }

    private let tokenizer: Tokenizer
    private let resolver: Resolver
    private let composer: Composer

    init(tokenizer: Tokenizer = Tokenizer(), resolver: Resolver = Resolver(), composer: Composer = Composer()) {
        self.tokenizer = tokenizer
        self.resolver = resolver
        self.composer = composer
    }

    func extract(from input: String, locale: Locale, now: Date, calendar: Calendar) -> Extraction {
        let normalizedOriginal = normalizedWhitespace(input)
        guard !normalizedOriginal.isEmpty else {
            return Extraction(strippedInput: normalizedOriginal, deadlineAt: nil)
        }

        let table = LocalePhrases.table(for: locale)
        guard let extraction = firstDeadlineMatch(in: input, locale: table, now: now, calendar: calendar) else {
            return Extraction(strippedInput: normalizedOriginal, deadlineAt: nil)
        }

        return extraction
    }

    private func firstDeadlineMatch(
        in input: String,
        locale: LocalePhrases,
        now: Date,
        calendar: Calendar
    ) -> Extraction? {
        let matches = markerMatches(in: input, locale: locale)
        for match in matches {
            let suffix = input[match.range.upperBound...]
            guard let datePhrase = datePhrasePrefix(in: suffix, locale: locale, now: now, calendar: calendar) else {
                continue
            }

            let removeRange = match.range.lowerBound..<datePhrase.range.upperBound
            let stripped = strippedInput(
                removing: removeRange,
                fallbackDateRange: datePhrase.range,
                from: input
            )
            return Extraction(strippedInput: stripped, deadlineAt: datePhrase.deadlineAt)
        }
        return nil
    }

    private func markerMatches(in input: String, locale: LocalePhrases) -> [MarkerMatch] {
        let patterns = markerPatterns(for: locale)
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        return patterns.flatMap { pattern -> [MarkerMatch] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return []
            }
            return regex.matches(in: input, range: nsRange).compactMap { result in
                guard let range = Range(result.range, in: input) else { return nil }
                return MarkerMatch(range: range)
            }
        }
        .sorted {
            if $0.range.lowerBound == $1.range.lowerBound {
                return input.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
                    > input.distance(from: $1.range.lowerBound, to: $1.range.upperBound)
            }
            return $0.range.lowerBound < $1.range.lowerBound
        }
    }

    private func markerPatterns(for locale: LocalePhrases) -> [String] {
        let boundary = #"(?<![\p{L}\p{N}])"#
        let end = #"(?![\p{L}\p{N}])"#
        if locale.languageCode == "pl" {
            return [
                boundary + #"najpóźniej\s+do"# + end,
                boundary + #"do\s+końca"# + end,
                boundary + #"do\s+dnia"# + end,
                boundary + #"termin"# + end,
                boundary + #"deadline"# + end,
            ]
        }
        return [
            boundary + #"no\s+later\s+than"# + end,
            boundary + #"due\s+by"# + end,
            boundary + #"deadline"# + end,
            boundary + #"by"# + end,
        ]
    }

    private func datePhrasePrefix(
        in suffix: Substring,
        locale: LocalePhrases,
        now: Date,
        calendar: Calendar
    ) -> DatePhrase? {
        let words = wordRanges(in: suffix)
        guard !words.isEmpty else { return nil }

        var best: DatePhrase?
        for count in 1...min(words.count, 5) {
            let candidateRange = words[0].lowerBound..<words[count - 1].upperBound
            let candidate = String(suffix[candidateRange])
            guard let deadlineAt = parsedDeadline(from: candidate, locale: locale, now: now, calendar: calendar) else {
                continue
            }
            best = DatePhrase(range: candidateRange, deadlineAt: deadlineAt)
        }
        return best
    }

    private func parsedDeadline(
        from candidate: String,
        locale: LocalePhrases,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let isPolishEndOfWeek =
            candidate.compare(
                "tygodnia",
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        if locale.languageCode == "pl", isPolishEndOfWeek {
            return endOfWeekDeadline(now: now, calendar: calendar)
        }

        let tokens = tokenizer.tokenize(candidate, locale: locale)
        let resolved = resolver.resolve(tokens, locale: locale, now: now, calendar: calendar)
        guard
            !resolved.isEmpty,
            resolved.allSatisfy(\.isDeadlineDateToken)
        else { return nil }

        let result = composer.compose(resolved, input: candidate, now: now, calendar: calendar)
        return result.startAt ?? result.dueAt
    }

    private func endOfWeekDeadline(now: Date, calendar: Calendar) -> Date {
        guard
            let week = calendar.dateInterval(of: .weekOfYear, for: now),
            let lastDay = calendar.date(byAdding: .day, value: 6, to: week.start)
        else {
            return calendar.startOfDay(for: now)
        }
        return calendar.startOfDay(for: lastDay)
    }

    private func wordRanges(in suffix: Substring) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = suffix.startIndex
        while index < suffix.endIndex {
            while index < suffix.endIndex, suffix[index].isWhitespace {
                index = suffix.index(after: index)
            }
            guard index < suffix.endIndex else { break }
            let start = index
            while index < suffix.endIndex, !suffix[index].isWhitespace {
                index = suffix.index(after: index)
            }
            ranges.append(start..<index)
        }
        return ranges
    }

    private func strippedInput(
        removing removeRange: Range<String.Index>,
        fallbackDateRange: Range<String.Index>,
        from input: String
    ) -> String {
        var stripped = input
        stripped.removeSubrange(removeRange)
        let normalized = normalizedWhitespace(stripped)
        guard normalized.isEmpty else { return normalized }

        var fallback = input
        fallback.removeSubrange(fallbackDateRange)
        return normalizedWhitespace(fallback)
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private struct MarkerMatch {
    let range: Range<String.Index>
}

private struct DatePhrase {
    let range: Range<String.Index>
    let deadlineAt: Date
}

extension Token {
    fileprivate var isDeadlineDateToken: Bool {
        switch self {
        case .relativeDay, .relativePhrase, .timeOfDay:
            return true
        default:
            return false
        }
    }
}
