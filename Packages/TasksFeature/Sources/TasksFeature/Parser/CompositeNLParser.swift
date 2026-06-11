import Foundation

/// Cascade parser: handcoded primary, FM augmentation only when handcoded
/// returns no date and no recurrence and confidence is below the cutoff.
/// Per spec §8, 95%+ of typical task captures stay on the handcoded fast
/// path with zero LM round-trips and zero latency.
public actor CompositeNLParser: NLParser {
    private let handcoded: HandcodedParser
    private let foundationModel: FoundationModelParser
    private let confidenceCutoff: Float
    private let deadlineExtractor: DeadlineExtractor

    public init(
        handcoded: HandcodedParser,
        foundationModel: FoundationModelParser,
        confidenceCutoff: Float = 0.7
    ) {
        self.handcoded = handcoded
        self.foundationModel = foundationModel
        self.confidenceCutoff = confidenceCutoff
        self.deadlineExtractor = DeadlineExtractor()
    }

    public func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult {
        let effectiveLocale = LocalePhrases.detectLocale(from: input) ?? locale
        let deadline = deadlineExtractor.extract(from: input, locale: effectiveLocale, now: now, calendar: calendar)
        let workingInput = deadline.strippedInput
        let pass1 = withDeadline(
            await handcoded.parse(workingInput, locale: effectiveLocale, now: now, calendar: calendar),
            deadlineAt: deadline.deadlineAt
        )
        let needsFM =
            pass1.dueAt == nil && pass1.deadlineAt == nil && pass1.recurrence == nil && pass1.confidence < confidenceCutoff

        guard needsFM else {
            return enrichDurationIfNeeded(pass1, input: workingInput, locale: effectiveLocale, calendar: calendar)
        }

        let pass2 = withDeadline(
            await foundationModel.parse(workingInput, locale: effectiveLocale, now: now, calendar: calendar),
            deadlineAt: deadline.deadlineAt
        )
        // FM successfully added structure → use it. Otherwise, fall back to
        // handcoded result so a failed FM round-trip never *removes* data.
        let fmAddedStructure =
            pass2.dueAt != nil || pass2.deadlineAt != nil || pass2.recurrence != nil || pass2.priority != nil
            || !pass2.tags.isEmpty || pass2.projectToken != nil
        if fmAddedStructure {
            return enrichDurationIfNeeded(pass2, input: workingInput, locale: effectiveLocale, calendar: calendar)
        }
        return enrichDurationIfNeeded(pass1, input: workingInput, locale: effectiveLocale, calendar: calendar)
    }

    private func enrichDurationIfNeeded(_ result: ParseResult, input: String, locale: Locale, calendar: Calendar) -> ParseResult {
        guard
            result.endAt == nil,
            let startAt = result.startAt,
            let duration = DurationExtractor.extract(from: input, locale: locale, startAt: startAt, calendar: calendar)
        else { return result }

        var enriched = result
        enriched.endAt = startAt.addingTimeInterval(duration.duration)
        return enriched
    }

    private func withDeadline(_ result: ParseResult, deadlineAt: Date?) -> ParseResult {
        guard let deadlineAt, result.deadlineAt == nil else { return result }
        var enriched = result
        enriched.deadlineAt = deadlineAt
        return enriched
    }
}
