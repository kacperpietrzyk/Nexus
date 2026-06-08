import Foundation

/// Pure presentation reducer over a `DeadlineRiskAnalyzer` projection (spec
/// §19.1). Collapses the raw `[DeadlineRisk]` into the small shape the Today
/// banner needs: how many tasks are `atRisk` vs `tight`, and which single task
/// is the most urgent (lowest projected slack) so the banner can surface one
/// "start X by …" call to action. Deterministic + UI-free so it is unit-testable
/// and reusable by any surface without a feature-module cross-import — mirrors
/// `EveningShutdownSummary`.
public struct DeadlineRiskSummary: Equatable, Sendable {
    /// Tasks projected to miss (`severity == .atRisk`), most-urgent first.
    public let atRiskTaskIDs: [UUID]
    /// Tasks with thin-but-positive slack (`severity == .tight`), most-urgent first.
    public let tightTaskIDs: [UUID]
    /// The single most pressing risk (lowest projected slack across both tiers),
    /// or nil when nothing is under pressure. Drives the banner's headline.
    public let mostUrgent: DeadlineRisk?

    public init(atRiskTaskIDs: [UUID], tightTaskIDs: [UUID], mostUrgent: DeadlineRisk?) {
        self.atRiskTaskIDs = atRiskTaskIDs
        self.tightTaskIDs = tightTaskIDs
        self.mostUrgent = mostUrgent
    }

    public var atRiskCount: Int { atRiskTaskIDs.count }
    public var tightCount: Int { tightTaskIDs.count }
    /// True when at least one task is `tight` or `atRisk` — the banner shows only then.
    public var hasPressure: Bool { mostUrgent != nil }

    /// Reduce a raw risk projection. `onTrack` entries are dropped (no pressure to
    /// surface, per spec §19.1). Ordering inside each tier and the `mostUrgent`
    /// pick are by ascending projected slack, tie-broken by task id, so identical
    /// input yields an identical summary (determinism matches the analyzer's).
    public static func make(from risks: [DeadlineRisk]) -> DeadlineRiskSummary {
        let pressured = risks.filter { $0.severity != .onTrack }
        let ordered = pressured.sorted { lhs, rhs in
            if lhs.projectedSlackHours != rhs.projectedSlackHours {
                return lhs.projectedSlackHours < rhs.projectedSlackHours
            }
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }
        return DeadlineRiskSummary(
            atRiskTaskIDs: ordered.filter { $0.severity == .atRisk }.map(\.taskID),
            tightTaskIDs: ordered.filter { $0.severity == .tight }.map(\.taskID),
            mostUrgent: ordered.first
        )
    }
}
