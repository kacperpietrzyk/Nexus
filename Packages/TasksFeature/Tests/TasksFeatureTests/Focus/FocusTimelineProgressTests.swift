import Foundation
import Testing

@testable import TasksFeature

@Suite("FocusTimelineProgress")
struct FocusTimelineProgressTests {
    private let start = Date(timeIntervalSince1970: 1_778_146_400)

    @Test("returns zero when no real start time exists")
    func noStart() {
        let now = start.addingTimeInterval(30 * 60)

        #expect(FocusTimelineProgress.progress(startAt: nil, endAt: start.addingTimeInterval(60 * 60), dueAt: nil, now: now) == 0)
        #expect(FocusTimelineProgress.elapsedMinutes(startAt: nil, now: now) == 0)
    }

    @Test("uses start to end window for elapsed progress")
    func startEndWindow() {
        let end = start.addingTimeInterval(120 * 60)
        let now = start.addingTimeInterval(30 * 60)

        #expect(FocusTimelineProgress.progress(startAt: start, endAt: end, dueAt: nil, now: now) == 0.25)
        #expect(FocusTimelineProgress.elapsedMinutes(startAt: start, now: now) == 30)
    }

    @Test("falls back to dueAt when endAt is absent")
    func dueFallback() {
        let due = start.addingTimeInterval(90 * 60)
        let now = start.addingTimeInterval(45 * 60)

        #expect(FocusTimelineProgress.progress(startAt: start, endAt: nil, dueAt: due, now: now) == 0.5)
    }

    @Test("clamps before start and after finish")
    func clamps() {
        let end = start.addingTimeInterval(60 * 60)

        #expect(FocusTimelineProgress.progress(startAt: start, endAt: end, dueAt: nil, now: start.addingTimeInterval(-10)) == 0)
        #expect(FocusTimelineProgress.progress(startAt: start, endAt: end, dueAt: nil, now: end.addingTimeInterval(10)) == 1)
    }
}
