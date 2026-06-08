import Foundation

/// Pure agent auto-derivation policy (Projects tier, spec §8). This is a
/// **suggestion only** — it never mutates a task and the caller must never let it
/// override a manual `assignedAgent`. The override discipline lives at the call
/// site, not here.
///
/// Policy: the presence of the `bug` domain label suggests `codex`; `feature`
/// suggests `claude`. Because domain labels are single-select (I5), `bug` and
/// `feature` cannot co-occur on one endpoint, so no tie-break is needed; `bug` is
/// checked first defensively. Returns `nil` when no label drives a suggestion.
public func suggestedAgent(forLabels labels: [Label]) -> AgentAssignee? {
    let domainNames = Set(
        labels
            .filter { $0.group == .domain && $0.deletedAt == nil }
            .map { $0.name.lowercased() }
    )
    if domainNames.contains(SystemLabel.bug.name) {
        return .codex
    }
    if domainNames.contains(SystemLabel.feature.name) {
        return .claude
    }
    return nil
}
