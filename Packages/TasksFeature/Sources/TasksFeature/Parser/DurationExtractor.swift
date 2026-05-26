import Foundation

public enum DurationExtractor {
    public struct Match {
        public let duration: TimeInterval
        public let consumed: [Range<String.Index>]

        public init(duration: TimeInterval, consumed: [Range<String.Index>]) {
            self.duration = duration
            self.consumed = consumed
        }
    }

    public static func extract(from input: String, locale: Locale, startAt: Date? = nil) -> Match? {
        switch locale.language.languageCode?.identifier {
        case "pl":
            return PolishMatcher.extract(from: input, startAt: startAt)
        default:
            return EnglishMatcher.extract(from: input, startAt: startAt)
        }
    }
}

private enum PolishMatcher {
    private static let maximumDuration: TimeInterval = 366 * 24 * 3600
    private static let numericStartBoundary = #"(?<![\p{L}\p{N}+\-.,])"#

    static func extract(from input: String, startAt: Date?) -> DurationExtractor.Match? {
        if let startAt, let match = untilTime(in: input, startAt: startAt) {
            return match
        }
        if let match = numericHoursAndHalf(in: input) {
            return match
        }
        if let match = numericHoursAndMinutes(in: input, withConnector: true) {
            return match
        }
        if let match = numericHoursAndMinutes(in: input, withConnector: false) {
            return match
        }
        if let match = numericHoursWithBareH(in: input) {
            return match
        }
        if let match = integerHours(in: input) {
            return match
        }
        if let match = integerMinutes(in: input) {
            return match
        }
        if let match = halfHour(in: input) {
            return match
        }
        if let match = spelledHours(in: input) {
            return match
        }
        if let match = spelledMinutes(in: input) {
            return match
        }
        return nil
    }

    private static func untilTime(in input: String, startAt: Date) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: #"(?<![\p{L}\p{N}])do\s+([01]?\d|2[0-3])(?::([0-5]\d))?(?![\p{L}\p{N}])"#
            ),
            let hourText = match.text(at: 1, in: input),
            let hour = Int(hourText)
        else { return nil }

        let minute = match.text(at: 2, in: input).flatMap(Int.init) ?? 0
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day], from: startAt)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let endAt = calendar.date(from: components) else { return nil }
        let duration = endAt.timeIntervalSince(startAt)
        guard duration > 0 else { return nil }
        return DurationExtractor.Match(duration: duration, consumed: [match.range])
    }

    private static func numericHoursAndHalf(in input: String) -> DurationExtractor.Match? {
        if let match = firstRegexMatch(
            in: input,
            pattern: numericStartBoundary + #"(\d+)\s+(?:godzina|godziny|godzin)\s+i\s+pół(?![\p{L}\p{N}])"#
        ) {
            guard let hoursText = match.text(at: 1, in: input),
                let hours = number(hoursText)
            else { return nil }
            return durationMatch(seconds: hours * 3600 + 1800, consumed: match.range)
        }

        guard
            let match = firstRegexMatch(
                in: input,
                pattern: #"(?<![\p{L}\p{N}])(?:godzina|godziny|godzin)\s+i\s+pół(?![\p{L}\p{N}])"#
            ),
            !hasSignedNumericPrefix(before: match.range.lowerBound, in: input)
        else { return nil }

        return DurationExtractor.Match(duration: 5400, consumed: [match.range])
    }

    private static func numericHoursAndMinutes(in input: String, withConnector: Bool) -> DurationExtractor.Match? {
        let connector = withConnector ? #"\s+i\s+"# : #"\s+"#
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + #"(\d+)\s+(?:godzina|godziny|godzin)"# + connector
                    + #"(\d+)\s*(?:minut|min)(?![\p{L}\p{N}])"#
            ),
            let hoursText = match.text(at: 1, in: input),
            let minutesText = match.text(at: 2, in: input),
            let hours = number(hoursText),
            let minutes = number(minutesText),
            hours > 0 || minutes > 0
        else { return nil }

        return durationMatch(seconds: hours * 3600 + minutes * 60, consumed: match.range)
    }

    private static func numericHoursWithBareH(in input: String) -> DurationExtractor.Match? {
        if let match = firstRegexMatch(
            in: input,
            pattern: numericStartBoundary + #"(\d+(?:[,.]\d+)?)\s*h(?![\p{L}\p{N}])"#
        ) {
            return decimalHourMatch(match, input: input)
        }
        if let match = firstRegexMatch(
            in: input,
            pattern: numericStartBoundary + #"(\d+[,.]\d+)\s+(?:godzina|godziny|godzin)(?![\p{L}\p{N}])"#
        ) {
            return decimalHourMatch(match, input: input)
        }
        return nil
    }

    private static func integerHours(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + #"(\d+)\s+(?:godzina|godziny|godzin)(?![\p{L}\p{N}])"#
            ),
            let hoursText = match.text(at: 1, in: input),
            let hours = number(hoursText),
            hours > 0
        else { return nil }

        return durationMatch(seconds: hours * 3600, consumed: match.range)
    }

    private static func integerMinutes(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + #"(\d+)\s*(?:minut|min)(?![\p{L}\p{N}])"#
            ),
            let minutesText = match.text(at: 1, in: input),
            let minutes = number(minutesText),
            minutes > 0
        else { return nil }

        return durationMatch(seconds: minutes * 60, consumed: match.range)
    }

    private static func halfHour(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: #"(?<![\p{L}\p{N}])pół\s+(?:godziny|godzina|godzin)(?![\p{L}\p{N}])"#
            )
        else { return nil }

        return DurationExtractor.Match(duration: 1800, consumed: [match.range])
    }

    private static func spelledHours(in input: String) -> DurationExtractor.Match? {
        let values = [
            "dwie": 2,
            "trzy": 3,
            "cztery": 4,
            "pięć": 5,
            "sześć": 6,
        ]
        let numberPattern = values.keys.sorted(by: { $0.count > $1.count }).joined(separator: "|")
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: #"(?<![\p{L}\p{N}])("# + numberPattern + #")\s+(?:godziny|godzin)(?![\p{L}\p{N}])"#
            ),
            let numberText = match.text(at: 1, in: input)?.lowercased(),
            let hours = values[numberText]
        else { return nil }

        return DurationExtractor.Match(duration: TimeInterval(hours * 3600), consumed: [match.range])
    }

    private static func spelledMinutes(in input: String) -> DurationExtractor.Match? {
        let values = [
            "czterdzieści pięć": 45,
            "trzydzieści": 30,
            "dwadzieścia": 20,
            "piętnaście": 15,
            "dziesięć": 10,
            "pięć": 5,
        ]
        let numberPattern = values.keys.sorted(by: { $0.count > $1.count }).joined(separator: "|")
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: #"(?<![\p{L}\p{N}])("# + numberPattern + #")\s+minut(?![\p{L}\p{N}])"#
            ),
            let numberText = match.text(at: 1, in: input)?.lowercased(),
            let minutes = values[numberText]
        else { return nil }

        return DurationExtractor.Match(duration: TimeInterval(minutes * 60), consumed: [match.range])
    }

    private static func decimalHourMatch(_ match: RegexMatch, input: String) -> DurationExtractor.Match? {
        guard let rawValue = match.text(at: 1, in: input),
            let hours = number(rawValue)
        else { return nil }
        return durationMatch(seconds: hours * 3600, consumed: match.range)
    }

    private static func number(_ raw: String) -> TimeInterval? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func durationMatch(seconds: TimeInterval, consumed range: Range<String.Index>) -> DurationExtractor.Match? {
        guard seconds.isFinite, seconds > 0, seconds <= maximumDuration else { return nil }
        return DurationExtractor.Match(duration: seconds, consumed: [range])
    }

    private static func hasSignedNumericPrefix(before index: String.Index, in input: String) -> Bool {
        let prefix = String(input[..<index])
        return prefix.range(of: #"[+\-]\d+(?:[,.]\d+)?\s+$"#, options: .regularExpression) != nil
    }
}

private enum EnglishMatcher {
    private static let maximumDuration: TimeInterval = 366 * 24 * 3600
    private static let numericStartBoundary = #"(?<![\p{L}\p{N}+\-.,])"#
    private static let phraseStartBoundary = #"(?<![\p{L}\p{N}])"#
    private static let optionalForPrefix = #"(?:for\s+)?"#

    static func extract(from input: String, startAt: Date?) -> DurationExtractor.Match? {
        if let startAt, let match = untilTime(in: input, startAt: startAt) {
            return match
        }
        if let match = halfHour(in: input) {
            return match
        }
        if let match = hoursAndHalf(in: input) {
            return match
        }
        if let match = numericHoursAndMinutes(in: input, withConnector: true) {
            return match
        }
        if let match = numericHoursAndMinutes(in: input, withConnector: false) {
            return match
        }
        if let match = numericHoursWithBareH(in: input) {
            return match
        }
        if let match = numericHours(in: input) {
            return match
        }
        if let match = numericMinutes(in: input) {
            return match
        }
        if let match = spelledHours(in: input) {
            return match
        }
        if let match = spelledMinutes(in: input) {
            return match
        }
        return nil
    }

    private static func untilTime(in input: String, startAt: Date) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: phraseStartBoundary + #"until\s+([01]?\d|2[0-3])(?::([0-5]\d))?\s*(am|pm)?(?![\p{L}\p{N}])"#
            ),
            let hourText = match.text(at: 1, in: input),
            let rawHour = Int(hourText)
        else { return nil }

        let meridiem = match.text(at: 3, in: input)?.lowercased()
        guard meridiem == nil || (1...12).contains(rawHour) else { return nil }

        let hour: Int
        switch meridiem {
        case "am":
            hour = rawHour == 12 ? 0 : rawHour
        case "pm":
            hour = rawHour == 12 ? 12 : rawHour + 12
        default:
            hour = rawHour
        }
        let minute = match.text(at: 2, in: input).flatMap(Int.init) ?? 0

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        var components = calendar.dateComponents([.year, .month, .day], from: startAt)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let endAt = calendar.date(from: components) else { return nil }
        let duration = endAt.timeIntervalSince(startAt)
        guard duration > 0 else { return nil }
        return DurationExtractor.Match(duration: duration, consumed: [match.range])
    }

    private static func halfHour(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: phraseStartBoundary + optionalForPrefix + #"half\s+(?:an\s+)?hour(?![\p{L}\p{N}])"#
            )
        else { return nil }

        return DurationExtractor.Match(duration: 1800, consumed: [match.range])
    }

    private static func hoursAndHalf(in input: String) -> DurationExtractor.Match? {
        if let match = firstRegexMatch(
            in: input,
            pattern: phraseStartBoundary + optionalForPrefix + #"an\s+hour\s+and\s+(?:a\s+)?half(?![\p{L}\p{N}])"#
        ) {
            return DurationExtractor.Match(duration: 5400, consumed: [match.range])
        }
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + optionalForPrefix + #"(\d+)\s+hours?\s+and\s+(?:a\s+)?half(?![\p{L}\p{N}])"#
            ),
            let hoursText = match.text(at: 1, in: input),
            let hours = number(hoursText)
        else { return nil }

        return durationMatch(seconds: hours * 3600 + 1800, consumed: match.range)
    }

    private static func numericHoursAndMinutes(in input: String, withConnector: Bool) -> DurationExtractor.Match? {
        let connector = withConnector ? #"\s+and\s+"# : #"\s+"#
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + optionalForPrefix + #"(\d+(?:[,.]\d+)?)\s+hours?"# + connector
                    + #"(\d+(?:[,.]\d+)?)\s*(?:minutes?|mins?)(?![\p{L}\p{N}])"#
            ),
            let hoursText = match.text(at: 1, in: input),
            let minutesText = match.text(at: 2, in: input),
            let hours = number(hoursText),
            let minutes = number(minutesText),
            hours > 0 || minutes > 0
        else { return nil }

        return durationMatch(seconds: hours * 3600 + minutes * 60, consumed: match.range)
    }

    private static func numericHoursWithBareH(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + optionalForPrefix + #"(\d+(?:[,.]\d+)?)\s*h(?![\p{L}\p{N}])"#
            )
        else { return nil }

        return decimalHourMatch(match, input: input)
    }

    private static func numericHours(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + optionalForPrefix + #"(\d+(?:[,.]\d+)?)\s+hours?(?![\p{L}\p{N}])"#
            )
        else { return nil }

        return decimalHourMatch(match, input: input)
    }

    private static func numericMinutes(in input: String) -> DurationExtractor.Match? {
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: numericStartBoundary + optionalForPrefix + #"(\d+(?:[,.]\d+)?)\s*(?:minutes?|mins?)(?![\p{L}\p{N}])"#
            ),
            let minutesText = match.text(at: 1, in: input),
            let minutes = number(minutesText),
            minutes > 0
        else { return nil }

        return durationMatch(seconds: minutes * 60, consumed: match.range)
    }

    private static func spelledHours(in input: String) -> DurationExtractor.Match? {
        let values = [
            "an": 1,
            "one": 1,
            "two": 2,
            "three": 3,
            "four": 4,
            "five": 5,
            "six": 6,
        ]
        let numberPattern = values.keys.sorted(by: { $0.count > $1.count }).joined(separator: "|")
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: phraseStartBoundary + optionalForPrefix + #"("# + numberPattern + #")\s+hours?(?![\p{L}\p{N}])"#
            ),
            let numberText = match.text(at: 1, in: input)?.lowercased(),
            let hours = values[numberText]
        else { return nil }

        return DurationExtractor.Match(duration: TimeInterval(hours * 3600), consumed: [match.range])
    }

    private static func spelledMinutes(in input: String) -> DurationExtractor.Match? {
        let values = [
            "forty five": 45,
            "thirty": 30,
            "twenty": 20,
            "fifteen": 15,
            "ten": 10,
            "five": 5,
        ]
        let numberPattern = values.keys.sorted(by: { $0.count > $1.count }).joined(separator: "|")
        guard
            let match = firstRegexMatch(
                in: input,
                pattern: phraseStartBoundary + optionalForPrefix + #"("# + numberPattern + #")\s+minutes?(?![\p{L}\p{N}])"#
            ),
            let numberText = match.text(at: 1, in: input)?.lowercased(),
            let minutes = values[numberText]
        else { return nil }

        return DurationExtractor.Match(duration: TimeInterval(minutes * 60), consumed: [match.range])
    }

    private static func decimalHourMatch(_ match: RegexMatch, input: String) -> DurationExtractor.Match? {
        guard let rawValue = match.text(at: 1, in: input),
            let hours = number(rawValue)
        else { return nil }
        return durationMatch(seconds: hours * 3600, consumed: match.range)
    }

    private static func number(_ raw: String) -> TimeInterval? {
        let normalized = raw.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func durationMatch(seconds: TimeInterval, consumed range: Range<String.Index>) -> DurationExtractor.Match? {
        guard seconds.isFinite, seconds > 0, seconds <= maximumDuration else { return nil }
        return DurationExtractor.Match(duration: seconds, consumed: [range])
    }
}

private struct RegexMatch {
    let range: Range<String.Index>
    let groups: [Range<String.Index>?]

    func text(at index: Int, in input: String) -> String? {
        guard groups.indices.contains(index), let range = groups[index] else { return nil }
        return String(input[range])
    }
}

private func firstRegexMatch(in input: String, pattern: String) -> RegexMatch? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let searchRange = NSRange(input.startIndex..<input.endIndex, in: input)
    guard let result = regex.firstMatch(in: input, range: searchRange),
        let range = Range(result.range, in: input)
    else { return nil }

    let groups = (0..<result.numberOfRanges).map { index -> Range<String.Index>? in
        let groupRange = result.range(at: index)
        guard groupRange.location != NSNotFound else { return nil }
        return Range(groupRange, in: input)
    }
    return RegexMatch(range: range, groups: groups)
}
