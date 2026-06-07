import Foundation

/// A duration estimate produced by a `DurationEstimator` (spec §5).
/// `seconds` is the estimated block length; `confidence ∈ [0, 1]` reflects how
/// trustworthy the estimate is (explicit = 1.0, history grows with samples,
/// fallback low).
public struct DurationEstimate: Equatable, Sendable {
    public var seconds: Int
    public var confidence: Double

    public init(seconds: Int, confidence: Double) {
        self.seconds = seconds
        self.confidence = confidence
    }
}

/// Estimates how long a task will take (spec §5). On-device, deterministic, and
/// dependency-free so the MLX-LLM refinement can later slot in behind the same
/// protocol with zero caller changes.
///
/// `history` is the corpus of completed tasks with a *known* duration — that is,
/// `durationSource == .explicit` and `estimatedDurationSeconds != nil` (spec
/// §4.2 keeps `startAt`/`endAt` generic, so the known duration is the persisted
/// `estimatedDurationSeconds`, never a start/end pair). Callers pre-filter the
/// corpus; the estimator skips any element lacking a usable duration defensively.
public protocol DurationEstimator: Sendable {
    func estimate(for task: TaskItem, history: [TaskItem]) -> DurationEstimate
}
