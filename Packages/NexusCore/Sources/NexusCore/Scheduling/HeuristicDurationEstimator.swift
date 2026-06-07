import Foundation

/// The MVP `DurationEstimator` (spec §5): a deterministic cascade
/// explicit → history → fallback, with zero EventKit / UI / RNG dependency.
///
/// Cascade:
/// 1. **Explicit** — if the task's `durationSource == .explicit` and it carries
///    an `estimatedDurationSeconds`, use it verbatim at confidence `1.0`.
/// 2. **History** — median of `estimatedDurationSeconds` over completed,
///    explicit-duration tasks that are "similar", tried in tiers: same
///    `projectID` → shared tag → shared title token. The first tier that has at
///    least `minimumSamples` (default 3) wins; confidence grows with sample
///    count up to a cap below `1.0`.
/// 3. **Fallback** — a title keyword / length heuristic (call ≈ 30m, review ≈
///    45m, write/draft ≈ 60m; otherwise the default), at low confidence.
///
/// "Known duration" means `estimatedDurationSeconds` with `durationSource ==
/// .explicit` — never a `startAt`/`endAt` pair (spec §4.2 keeps those generic).
public struct HeuristicDurationEstimator: DurationEstimator {
    /// Minimum number of similar completed tasks required to trust a history
    /// tier (spec §5: "min. N samples, e.g. ≥3").
    public let minimumSamples: Int
    /// Default duration when no history and no keyword matches (spec §5: 30 min).
    public let fallbackSeconds: Int

    public init(minimumSamples: Int = 3, fallbackSeconds: Int = 30 * 60) {
        self.minimumSamples = minimumSamples
        self.fallbackSeconds = fallbackSeconds
    }

    public func estimate(for task: TaskItem, history: [TaskItem]) -> DurationEstimate {
        // 1. Explicit — authoritative, confidence 1.0.
        if task.durationSource == .explicit, let seconds = task.estimatedDurationSeconds, seconds > 0 {
            return DurationEstimate(seconds: seconds, confidence: 1.0)
        }

        // Corpus: completed tasks with a known (explicit) duration. Defensive
        // pre-filter even though the caller is expected to pass exactly these.
        let corpus = history.filter { candidate in
            candidate.status == .done
                && candidate.durationSource == .explicit
                && (candidate.estimatedDurationSeconds ?? 0) > 0
                && candidate.id != task.id
        }

        // 2. History tiers: project → tag → title token. First tier with enough
        // samples wins.
        if let estimate = historyEstimate(for: task, corpus: corpus) {
            return estimate
        }

        // 3. Fallback heuristic.
        return fallbackEstimate(for: task)
    }

    // MARK: - History

    private func historyEstimate(for task: TaskItem, corpus: [TaskItem]) -> DurationEstimate? {
        let tiers: [[TaskItem]] = [
            projectMatches(for: task, in: corpus),
            tagMatches(for: task, in: corpus),
            titleTokenMatches(for: task, in: corpus),
        ]
        for tier in tiers where tier.count >= minimumSamples {
            let durations = tier.compactMap { $0.estimatedDurationSeconds }.sorted()
            guard !durations.isEmpty else { continue }
            return DurationEstimate(
                seconds: median(of: durations),
                confidence: historyConfidence(sampleCount: durations.count)
            )
        }
        return nil
    }

    private func projectMatches(for task: TaskItem, in corpus: [TaskItem]) -> [TaskItem] {
        guard let projectID = task.projectID else { return [] }
        return corpus.filter { $0.projectID == projectID }
    }

    private func tagMatches(for task: TaskItem, in corpus: [TaskItem]) -> [TaskItem] {
        let tags = Set(task.tags)
        guard !tags.isEmpty else { return [] }
        return corpus.filter { !Set($0.tags).isDisjoint(with: tags) }
    }

    private func titleTokenMatches(for task: TaskItem, in corpus: [TaskItem]) -> [TaskItem] {
        let tokens = Set(Tokenizer.tokenize(task.title))
        guard !tokens.isEmpty else { return [] }
        return corpus.filter { !Set(Tokenizer.tokenize($0.title)).isDisjoint(with: tokens) }
    }

    /// Confidence rises with the sample count but never reaches `1.0` (that is
    /// reserved for explicit). Deterministic: 3 samples → 0.5, asymptotically
    /// approaching the cap.
    private func historyConfidence(sampleCount: Int) -> Double {
        let cap = 0.9
        let base = 0.5
        guard sampleCount > minimumSamples else { return base }
        let extra = Double(sampleCount - minimumSamples)
        // Diminishing returns: each extra sample adds a shrinking increment.
        let grown = base + (cap - base) * (extra / (extra + Double(minimumSamples)))
        return min(cap, grown)
    }

    // MARK: - Fallback

    private func fallbackEstimate(for task: TaskItem) -> DurationEstimate {
        let tokens = Set(Tokenizer.tokenize(task.title))
        // Order matters only for documentation; the buckets are disjoint by
        // intent, but if a title hits two we take the longest deterministically.
        var matched: Int?
        if tokens.contains("write") || tokens.contains("draft") {
            matched = max(matched ?? 0, 60 * 60)
        }
        if tokens.contains("review") {
            matched = max(matched ?? 0, 45 * 60)
        }
        if tokens.contains("call") {
            matched = max(matched ?? 0, 30 * 60)
        }
        if let matched {
            return DurationEstimate(seconds: matched, confidence: 0.3)
        }
        return DurationEstimate(seconds: fallbackSeconds, confidence: 0.1)
    }

    // MARK: - Math

    /// Deterministic median of a pre-sorted, non-empty array. Even counts average
    /// the two central values (integer-floored).
    private func median(of sorted: [Int]) -> Int {
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        let lower = sorted[(count / 2) - 1]
        let upper = sorted[count / 2]
        return (lower + upper) / 2
    }
}
