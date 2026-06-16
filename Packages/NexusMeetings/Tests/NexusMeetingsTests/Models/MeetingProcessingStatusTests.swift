import Testing

@testable import NexusMeetings

@Suite struct MeetingProcessingStatusHandoffTests {
    @Test func awaitingAndClaimedAreInFlight() {
        #expect(MeetingProcessingStatus.isInFlight(MeetingProcessingStatus.awaitingExternalSummary.rawValue))
        #expect(MeetingProcessingStatus.isInFlight(MeetingProcessingStatus.claimedExternalSummary.rawValue))
    }

    @Test func rawValuesAreStable() {
        #expect(MeetingProcessingStatus.awaitingExternalSummary.rawValue == "awaiting-external-summary")
        #expect(MeetingProcessingStatus.claimedExternalSummary.rawValue == "claimed-external-summary")
    }
}
