import Foundation

/// Lifecycle of a `Cycle` (Tranche 2, Linear L1). Manual + assisted:
/// `upcoming → active → completed`, no auto-rollover (invariant I-C1 — the
/// user is the only mutator; end-of-cycle is a prompt, wired in Plan C).
/// Stable raw values — they land in CloudKit, never rename after introduction
/// (pinned by test).
public enum CycleStatus: String, Codable, Sendable, CaseIterable {
    case upcoming
    case active
    case completed
}
