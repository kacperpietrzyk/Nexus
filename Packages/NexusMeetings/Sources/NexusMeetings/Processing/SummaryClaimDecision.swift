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

    /// Whether the HELPER should re-arm a transcript-complete-but-summary-pending
    /// meeting on its own relaunch. `awaiting` always re-arms (no live claim). A
    /// `claimed` meeting is only reclaimed when the claim has gone STALE (older than
    /// `staleness`) or its claim time is unknown (pre-migration) — otherwise a live
    /// app session owns it and must be left alone (avoids a double summary).
    public static func shouldReclaimOnHelperLaunch(
        status: String, claimedAt: Date?, now: Date, staleness: TimeInterval
    ) -> Bool {
        if status == MeetingProcessingStatus.awaitingExternalSummary.rawValue { return true }
        guard status == MeetingProcessingStatus.claimedExternalSummary.rawValue else { return false }
        guard let claimedAt else { return true }
        return now.timeIntervalSince(claimedAt) > staleness
    }
}
