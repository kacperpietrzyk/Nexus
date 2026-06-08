import Foundation

/// Classification of a `Label` (Projects tier, spec §4.4 / §7). The group governs
/// the single-select policy enforced by `LabelRepository`:
///
/// - `domain` (feature/bug/infra/security) — **single-select** per endpoint.
/// - `gate` (needsDecision/decided) — **single-select** per endpoint.
/// - `free` (any user-created) — **multi-select** (accumulates).
///
/// Raw values are CloudKit-bound (stored on `Label.groupRaw`) and MUST NEVER be
/// renamed without a migration.
public enum LabelGroup: String, Codable, Sendable, CaseIterable {
    case domain
    case gate
    case free

    /// Whether assigning a label in this group removes any prior label of the
    /// same group from the endpoint (invariant I5, spec §7). `free` accumulates.
    public var isSingleSelect: Bool {
        switch self {
        case .domain, .gate:
            return true
        case .free:
            return false
        }
    }
}
