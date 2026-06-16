import Foundation
import Testing
@testable import NexusMeetings

@Suite struct HandoffNotificationTests {
    @Test func parseRoundTrip() {
        let id = UUID()
        let note = Notification(
            name: MeetingSummaryHandoffNotification.needsExternalSummary,
            object: nil,
            userInfo: ["meetingID": id.uuidString, "folderPath": "/tmp/x"]
        )
        let parsed = MeetingSummaryHandoffNotification.parse(note)
        #expect(parsed?.id == id)
        #expect(parsed?.folder.path == "/tmp/x")
    }

    @Test func parseRejectsMissingFields() {
        let note = Notification(
            name: MeetingSummaryHandoffNotification.needsExternalSummary,
            object: nil,
            userInfo: [:]
        )
        #expect(MeetingSummaryHandoffNotification.parse(note) == nil)
    }
}

@Suite struct SummaryDecisionTests {
    @Test func fallbackRunsOnlyWhenAwaiting() {
        #expect(
            SummaryFallbackDecision.shouldRun(
                currentStatus: MeetingProcessingStatus.awaitingExternalSummary.rawValue
            ))
        #expect(
            !SummaryFallbackDecision.shouldRun(
                currentStatus: MeetingProcessingStatus.claimedExternalSummary.rawValue
            ))
        #expect(
            !SummaryFallbackDecision.shouldRun(
                currentStatus: MeetingProcessingStatus.ready.rawValue
            ))
    }

    @Test func claimOnlyWhenAwaiting() {
        #expect(
            SummaryClaimDecision.canClaim(
                currentStatus: MeetingProcessingStatus.awaitingExternalSummary.rawValue
            ))
        #expect(
            !SummaryClaimDecision.canClaim(
                currentStatus: MeetingProcessingStatus.claimedExternalSummary.rawValue
            ))
        #expect(
            !SummaryClaimDecision.canClaim(
                currentStatus: MeetingProcessingStatus.ready.rawValue
            ))
    }
}
