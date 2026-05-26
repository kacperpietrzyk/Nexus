import Testing

@testable import NexusMeetings

@MainActor
@Test func summaryViewRendersMarkdown() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let meeting = MeetingsTestSupport.meeting(summary: "## TL;DR\nKrótkie spotkanie.")
    try repo.insert(meeting)
    _ = SummaryView(meetingID: meeting.id, repository: repo)
}
