import Foundation

public enum MeetingDecomposeInsight {
    /// Returns nil if summary is blank or actionItemIDs non-empty (pipeline already created tasks).
    /// Otherwise delegates to the coordinator to produce a decomposition Proposal.
    @MainActor
    public static func proposalIfEligible(
        summary: String,
        actionItemIDs: [UUID],
        focus: ContextFocus,
        coordinator: MeetingDecomposeCoordinator
    ) async throws -> Proposal? {
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard actionItemIDs.isEmpty else { return nil }
        return try await coordinator.decompose(summary: summary, focus: focus)
    }

    public static func dedupeKey(meetingID: UUID) -> String {
        "meeting_decompose:\(meetingID.uuidString)"
    }
}
