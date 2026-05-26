import Foundation
import NexusAI
import NexusCore

/// LM-augmented parser. Wraps `AIRouter` with a JSON-contract prompt; the
/// router picks Apple Intelligence first (per spec D5) so the round trip
/// stays on-device and free.
///
/// Spec deviation: spec §8 calls for `AIRouter.complete(task:outputSchema:)`
/// with a native `@Generable` schema; that API does not exist in the current
/// router (`AIResponse.text: String`). 1c locks the JSON-prompt contract;
/// native `@Generable` escalation is a deferred follow-up.
public actor FoundationModelParser: NLParser {
    private let router: AIRouter
    private let connectivity: ConnectivityPreference

    public init(router: AIRouter, connectivity: ConnectivityPreference = .offlineOnly) {
        self.router = router
        self.connectivity = connectivity
    }

    public func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult {
        // calendar is currently unused by the FM path (the prompt encodes
        // dates as relative-to-`now` strings interpreted by the model), but
        // we accept it to satisfy the NLParser contract — and so a future
        // revision can pin TZ formatting if/when the prompt template needs it.
        _ = calendar
        let prompt = FMPromptTemplate.make(input: input, now: now, locale: locale)
        let request = AIRequest(
            prompt: prompt,
            capability: .generate,
            connectivity: connectivity,
            cost: .free,
            providerPreference: .auto
        )
        do {
            let response = try await router.route(request)
            return decode(response.text, fallbackTitle: input)
        } catch {
            return ParseResult.empty(title: input.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func decode(_ text: String, fallbackTitle: String) -> ParseResult {
        guard let data = JSONExtractor.firstObject(in: text) else {
            return ParseResult.empty(title: fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let decoder = JSONDecoder()
        guard let schema = try? decoder.decode(FMParseSchema.self, from: data) else {
            return ParseResult.empty(title: fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return mapToResult(schema)
    }

    private func mapToResult(_ schema: FMParseSchema) -> ParseResult {
        let dueAt: Date? = schema.dueAt.flatMap { ISO8601DateFormatter.fixedFM.date(from: $0) }
        let startAt: Date? = schema.startAt.flatMap { ISO8601DateFormatter.fixedFM.date(from: $0) }
        let endAt: Date? = schema.endAt.flatMap { ISO8601DateFormatter.fixedFM.date(from: $0) }
        let deadlineAt: Date? = schema.deadlineAt.flatMap { ISO8601DateFormatter.fixedFM.date(from: $0) }
        let priority: TaskPriority? = schema.priority.flatMap { TaskPriority(rawValue: $0) }
        // Strip leading `#` for parity with `Tokenizer.classify`, which calls
        // `dropFirst()` on hashtag tokens. LMs emit either form depending on
        // prompt nuance; normalizing here keeps cross-path output stable.
        let tags =
            schema.tags?.map {
                $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            } ?? []
        // Confidence is fixed at 0.8 for FM augmentation — the LM is opaque,
        // so we publish a single steady value. CompositeNLParser uses this
        // when reporting the final cascade decision to the UI.
        return ParseResult(
            title: schema.title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            deadlineAt: deadlineAt,
            priority: priority,
            tags: tags,
            recurrence: schema.recurrence,
            confidence: 0.8
        )
    }
}
