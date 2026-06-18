import Foundation
import Testing

@testable import NexusMeetings

@Suite("TodayMeetingSelector")
struct TodayMeetingSelectorTests {
    // Reference "now": 2024-03-15 12:00:00 UTC
    private static let now = Date(timeIntervalSince1970: 1_710_504_000)
    private static let cal = Calendar.current

    // MARK: - Helpers

    private func makeProcessed(startedAt: Date, isPinned: Bool = false, pinnedAt: Date? = nil) -> Meeting {
        let m = MeetingsTestSupport.meeting(startedAt: startedAt, status: .ready)
        m.processedAt = TodayMeetingSelectorTests.now
        m.isPinned = isPinned
        m.pinnedAt = pinnedAt
        return m
    }

    /// A date that is within the same calendar day as `now` but earlier.
    private var todayEarlier: Date {
        // 6 hours before now but still same day
        TodayMeetingSelectorTests.now.addingTimeInterval(-6 * 3600)
    }

    /// A date that is 2 days before now (not today).
    private var yesterday: Date {
        TodayMeetingSelectorTests.now.addingTimeInterval(-2 * 24 * 3600)
    }

    // MARK: - Tests

    @Test("empty candidates returns nil")
    func emptyReturnsNil() {
        let result = TodayMeetingSelector.select([], now: TodayMeetingSelectorTests.now, calendar: TodayMeetingSelectorTests.cal)
        #expect(result == nil)
    }

    @Test("pinned beats today meeting")
    func pinnedBeatsToday() {
        let pinned = makeProcessed(startedAt: yesterday, isPinned: true, pinnedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-1))
        let todayMeeting = makeProcessed(startedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-1800))
        let result = TodayMeetingSelector.select(
            [todayMeeting, pinned],
            now: TodayMeetingSelectorTests.now,
            calendar: TodayMeetingSelectorTests.cal
        )
        #expect(result?.id == pinned.id)
    }

    @Test("most-recently pinned wins when multiple are pinned")
    func mostRecentPinnedWins() {
        let olderPinned = makeProcessed(
            startedAt: yesterday,
            isPinned: true,
            pinnedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-200)
        )
        let newerPinned = makeProcessed(
            startedAt: yesterday.addingTimeInterval(-3600),
            isPinned: true,
            pinnedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-100)
        )
        let result = TodayMeetingSelector.select(
            [olderPinned, newerPinned],
            now: TodayMeetingSelectorTests.now,
            calendar: TodayMeetingSelectorTests.cal
        )
        #expect(result?.id == newerPinned.id)
    }

    @Test("today beats older processed meeting")
    func todayBeatsOlderProcessed() {
        let older = makeProcessed(startedAt: yesterday)
        let todayMeeting = makeProcessed(startedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-1800))
        let result = TodayMeetingSelector.select(
            [older, todayMeeting],
            now: TodayMeetingSelectorTests.now,
            calendar: TodayMeetingSelectorTests.cal
        )
        #expect(result?.id == todayMeeting.id)
    }

    @Test("most-recent today meeting wins when multiple are today")
    func mostRecentTodayWins() {
        let earlierToday = makeProcessed(startedAt: todayEarlier)
        let laterToday = makeProcessed(startedAt: TodayMeetingSelectorTests.now.addingTimeInterval(-1800))
        let result = TodayMeetingSelector.select(
            [earlierToday, laterToday],
            now: TodayMeetingSelectorTests.now,
            calendar: TodayMeetingSelectorTests.cal
        )
        #expect(result?.id == laterToday.id)
    }

    @Test("falls back to most-recent processed when none pinned and none today")
    func fallsBackToMostRecentProcessed() {
        let older = makeProcessed(startedAt: yesterday.addingTimeInterval(-3600))
        let newer = makeProcessed(startedAt: yesterday)
        let result = TodayMeetingSelector.select(
            [older, newer],
            now: TodayMeetingSelectorTests.now,
            calendar: TodayMeetingSelectorTests.cal
        )
        #expect(result?.id == newer.id)
    }
}
