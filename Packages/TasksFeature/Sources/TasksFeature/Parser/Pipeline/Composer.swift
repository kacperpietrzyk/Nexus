import Foundation
import NexusCore

/// Combines resolved tokens into a `ParseResult`. Title is the residual word
/// stream joined by spaces. Typed tokens fold into dueAt, startAt, and other
/// `ParseResult` fields. Date math uses `Calendar(.iso8601)` with the user's
/// current time zone — "14:00 jutro" must resolve to local 14:00, not UTC.
///
/// `pendingTimeOfDay` is collected across the full token pass, then anchored on
/// `dueAt ?? today_midnight` so that token order never matters — "jutro rano"
/// and "rano jutro" both produce startAt on tomorrow's date.
internal struct Composer: Sendable {
    func compose(
        _ tokens: [Token],
        input: String,
        now: Date = Date(),
        calendar: Calendar = ParserCalendar.production
    ) -> ParseResult {
        var titleParts: [String] = []
        var dueAt: Date?
        var pendingTimeOfDay: TimeInterval?
        var priority: TaskPriority?
        var tags: [String] = []
        var projectToken: String?
        var recurrence: String?
        var maxConfidence: Float = 0.0

        for token in tokens {
            switch token {
            case .residual(let s):
                titleParts.append(s)
            case .relativeDay(let offset, let confidence):
                dueAt = startOfOffsetDay(now: now, offset: offset, calendar: calendar)
                maxConfidence = max(maxConfidence, confidence)
            case .relativePhrase(let amount, let unitDays, let confidence):
                let totalDays = amount * unitDays
                dueAt = startOfOffsetDay(now: now, offset: totalDays, calendar: calendar)
                maxConfidence = max(maxConfidence, confidence)
            case .timeOfDay(let secondsIntoDay, let confidence):
                pendingTimeOfDay = secondsIntoDay
                maxConfidence = max(maxConfidence, confidence)
            case .priority(let p, let confidence):
                priority = p
                maxConfidence = max(maxConfidence, confidence)
            case .tag(let body, let confidence):
                tags.append(body)
                maxConfidence = max(maxConfidence, confidence)
            case .project(let body, let confidence):
                if projectToken == nil {
                    projectToken = body
                    maxConfidence = max(maxConfidence, confidence)
                } else {
                    // Single-project rule: first @token wins; later ones stay
                    // in the title verbatim so typed text is never dropped.
                    titleParts.append("@\(body)")
                }
            case .recurrence(let rrule, let confidence):
                recurrence = rrule
                maxConfidence = max(maxConfidence, confidence)
            default:
                break
            }
        }

        let startAt: Date? = pendingTimeOfDay.map { secs in
            let base = dueAt ?? calendar.startOfDay(for: now)
            return base.addingTimeInterval(secs)
        }

        let title =
            titleParts.isEmpty
            ? input.trimmingCharacters(in: .whitespacesAndNewlines)
            : titleParts.joined(separator: " ")

        return ParseResult(
            title: title,
            dueAt: dueAt,
            startAt: startAt,
            priority: priority,
            tags: tags,
            projectToken: projectToken,
            recurrence: recurrence,
            confidence: maxConfidence
        )
    }

    private func startOfOffsetDay(now: Date, offset: Int, calendar: Calendar) -> Date {
        let base = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }
}
