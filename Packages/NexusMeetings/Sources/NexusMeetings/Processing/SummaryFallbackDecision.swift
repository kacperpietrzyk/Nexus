import Foundation

public enum SummaryFallbackDecision {
    /// The helper only completes a deferred summary itself if the app never
    /// claimed it (status is still `awaiting-external-summary`).
    public static func shouldRun(currentStatus: String) -> Bool {
        currentStatus == MeetingProcessingStatus.awaitingExternalSummary.rawValue
    }
}
