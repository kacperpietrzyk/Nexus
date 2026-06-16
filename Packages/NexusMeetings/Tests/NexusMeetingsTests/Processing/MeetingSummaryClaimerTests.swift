import Foundation
import Testing
@testable import NexusMeetings

@MainActor
@Suite struct MeetingSummaryClaimerTests {
    private func awaitingMeeting() -> Meeting {
        let m = Meeting(
            title: "t",
            startedAt: Date(timeIntervalSince1970: 0),
            detectionSource: .auto,
            transcriptText: "x"
        )
        m.processingStatus = MeetingProcessingStatus.awaitingExternalSummary.rawValue
        return m
    }

    @Test func claimsAwaitingAndRuns() {
        let m = awaitingMeeting()
        var claimed = false
        var ran = false
        let c = MeetingSummaryClaimer(
            pendingMeetings: { [m] },
            find: { _ in m },
            claim: { _ in claimed = true },
            runContinuation: { _, _ in ran = true },
            folderForMeeting: { _ in URL(fileURLWithPath: "/tmp") }
        )
        c.claimAndRun(meetingID: m.id, audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(claimed)
        #expect(ran)
    }

    @Test func skipsWhenAlreadyClaimed() {
        let m = awaitingMeeting()
        m.processingStatus = MeetingProcessingStatus.claimedExternalSummary.rawValue
        var claimed = false
        var ran = false
        let c = MeetingSummaryClaimer(
            pendingMeetings: { [m] },
            find: { _ in m },
            claim: { _ in claimed = true },
            runContinuation: { _, _ in ran = true },
            folderForMeeting: { _ in URL(fileURLWithPath: "/tmp") }
        )
        c.claimAndRun(meetingID: m.id, audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(!claimed)
        #expect(!ran)
    }

    @Test func sweepClaimsOnlyAwaiting() {
        let awaiting = awaitingMeeting()
        let ready = awaitingMeeting()
        ready.processingStatus = MeetingProcessingStatus.ready.rawValue
        var claimedIDs: [UUID] = []
        let c = MeetingSummaryClaimer(
            pendingMeetings: { [awaiting, ready] },
            find: { id in [awaiting, ready].first { $0.id == id } },
            claim: { claimedIDs.append($0.id) },
            runContinuation: { _, _ in },
            folderForMeeting: { _ in URL(fileURLWithPath: "/tmp") }
        )
        c.sweep()
        #expect(claimedIDs == [awaiting.id])
    }

    @Test func sweepRecoversStuckClaimed() {
        let stuck = awaitingMeeting()
        stuck.processingStatus = MeetingProcessingStatus.claimedExternalSummary.rawValue
        var claimed = false
        var ran = false
        let c = MeetingSummaryClaimer(
            pendingMeetings: { [stuck] },
            find: { _ in stuck },
            claim: { _ in claimed = true },
            runContinuation: { _, _ in ran = true },
            folderForMeeting: { _ in URL(fileURLWithPath: "/tmp") }
        )
        c.sweep()
        #expect(claimed)
        #expect(ran)
    }

    @Test func liveClaimAndRunSkipsAlreadyClaimed() {
        let stuck = awaitingMeeting()
        stuck.processingStatus = MeetingProcessingStatus.claimedExternalSummary.rawValue
        var claimed = false
        var ran = false
        let c = MeetingSummaryClaimer(
            pendingMeetings: { [stuck] },
            find: { _ in stuck },
            claim: { _ in claimed = true },
            runContinuation: { _, _ in ran = true },
            folderForMeeting: { _ in URL(fileURLWithPath: "/tmp") }
        )
        c.claimAndRun(meetingID: stuck.id, audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(!claimed)
        #expect(!ran)
    }
}
