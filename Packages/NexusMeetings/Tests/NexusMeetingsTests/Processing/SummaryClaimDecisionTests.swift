import Foundation
import Testing

@testable import NexusMeetings

private let base = Date(timeIntervalSince1970: 1_700_000_000)
private let staleness: TimeInterval = 1800

@Test func awaitingAlwaysReclaimsRegardlessOfClaimedAt() {
    #expect(
        SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.awaitingExternalSummary.rawValue,
            claimedAt: nil,
            now: base,
            staleness: staleness
        )
    )
    #expect(
        SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.awaitingExternalSummary.rawValue,
            claimedAt: base,
            now: base,
            staleness: staleness
        )
    )
}

@Test func recentClaimIsNotReclaimed() {
    #expect(
        !SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.claimedExternalSummary.rawValue,
            claimedAt: base,
            now: base,
            staleness: staleness
        )
    )
}

@Test func staleClaimIsReclaimed() {
    #expect(
        SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.claimedExternalSummary.rawValue,
            claimedAt: base.addingTimeInterval(-3600),
            now: base,
            staleness: staleness
        )
    )
}

@Test func claimWithUnknownTimeIsReclaimed() {
    #expect(
        SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.claimedExternalSummary.rawValue,
            claimedAt: nil,
            now: base,
            staleness: staleness
        )
    )
}

@Test func unrelatedStatusIsNeverReclaimed() {
    #expect(
        !SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.ready.rawValue,
            claimedAt: nil,
            now: base,
            staleness: staleness
        )
    )
    #expect(
        !SummaryClaimDecision.shouldReclaimOnHelperLaunch(
            status: MeetingProcessingStatus.queued.rawValue,
            claimedAt: base,
            now: base,
            staleness: staleness
        )
    )
}
