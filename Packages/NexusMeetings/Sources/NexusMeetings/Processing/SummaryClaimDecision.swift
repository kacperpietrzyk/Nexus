import Foundation

public enum SummaryClaimDecision {
    /// The app claims a deferred summary only while it is still awaiting (the
    /// compare half of a cross-process compare-and-set).
    public static func canClaim(currentStatus: String) -> Bool {
        currentStatus == MeetingProcessingStatus.awaitingExternalSummary.rawValue
    }

    /// On a fresh app launch, a meeting still marked `claimedExternalSummary`
    /// belongs to a previous app session that died before finishing — no job is
    /// running in this process, so it is safe to reclaim and re-run. (The live
    /// notification path must NOT use this — only the launch sweep.)
    public static func canRecoverOnLaunch(currentStatus: String) -> Bool {
        currentStatus == MeetingProcessingStatus.awaitingExternalSummary.rawValue
            || currentStatus == MeetingProcessingStatus.claimedExternalSummary.rawValue
    }
}
