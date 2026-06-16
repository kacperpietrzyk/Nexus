import Foundation
import Testing
@testable import NexusMeetings

@MainActor
@Suite struct SummaryDeferralTests {
    private func makeMeeting() -> Meeting {
        Meeting(
            title: "Test meeting",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            detectionSource: .auto,
            transcriptText: "hello"
        )
    }

    @Test func assistantModelDefersAndSchedules() async {
        var posted = false
        var scheduled = false
        var summarized = false
        var awaited = false
        let p = MeetingSummaryDeferralProcessor(
            transcribe: { _, _ in },
            summarize: { _, _ in summarized = true },
            preference: { .assistantModel },
            markAwaiting: { _ in awaited = true },
            postNeedsSummary: { _, _ in posted = true },
            scheduleFallback: { _, _ in scheduled = true }
        )
        await p.process(meeting: makeMeeting(), audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(awaited && posted && scheduled)
        #expect(!summarized)
    }

    @Test func appleIntelligenceRunsInline() async {
        var posted = false
        var summarized = false
        let p = MeetingSummaryDeferralProcessor(
            transcribe: { _, _ in },
            summarize: { _, _ in summarized = true },
            preference: { .appleIntelligence },
            markAwaiting: { _ in },
            postNeedsSummary: { _, _ in posted = true },
            scheduleFallback: { _, _ in }
        )
        await p.process(meeting: makeMeeting(), audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(summarized)
        #expect(!posted)
    }

    @Test func transcriptionFailureStopsBeforeDeferral() async {
        var posted = false
        var summarized = false
        struct Boom: Error {}
        let p = MeetingSummaryDeferralProcessor(
            transcribe: { _, _ in throw Boom() },
            summarize: { _, _ in summarized = true },
            preference: { .assistantModel },
            markAwaiting: { _ in },
            postNeedsSummary: { _, _ in posted = true },
            scheduleFallback: { _, _ in }
        )
        await p.process(meeting: makeMeeting(), audioFolder: URL(fileURLWithPath: "/tmp"))
        #expect(!posted && !summarized)
    }

    @Test func schedulerRunsWhenStillAwaiting() async {
        let id = UUID()
        var ran = false
        let s = SummaryFallbackScheduler(
            timeout: .milliseconds(10),
            status: { _ in MeetingProcessingStatus.awaitingExternalSummary.rawValue },
            run: { _, _ in ran = true }
        )
        s.schedule(meetingID: id, audioFolder: URL(fileURLWithPath: "/tmp"))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(ran)
    }

    @Test func schedulerSkipsWhenClaimed() async {
        let id = UUID()
        var ran = false
        let s = SummaryFallbackScheduler(
            timeout: .milliseconds(10),
            status: { _ in MeetingProcessingStatus.claimedExternalSummary.rawValue },
            run: { _, _ in ran = true }
        )
        s.schedule(meetingID: id, audioFolder: URL(fileURLWithPath: "/tmp"))
        try? await Task.sleep(for: .milliseconds(500))
        #expect(!ran)
    }
}
