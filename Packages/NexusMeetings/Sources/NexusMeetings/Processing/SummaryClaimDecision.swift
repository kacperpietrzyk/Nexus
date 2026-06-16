import Foundation

public enum SummaryClaimDecision {
    /// The app claims a deferred summary only while it is still awaiting (the
    /// compare half of a cross-process compare-and-set).
    public static func canClaim(currentStatus: String) -> Bool {
        currentStatus == MeetingProcessingStatus.awaitingExternalSummary.rawValue
    }
}
