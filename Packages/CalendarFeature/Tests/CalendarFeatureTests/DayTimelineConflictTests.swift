import Foundation
import NexusCore
import Testing

@testable import CalendarFeature

@Suite("DayTimelineLayout conflicts")
@MainActor
struct DayTimelineConflictTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // 2026-06-08 09:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_780_650_000)

    @Test("blocks listed in conflictedBlockIDs map to conflicted items; others do not")
    func conflictedMapping() {
        let conflicted = ScheduledBlock(taskID: UUID(), start: now, end: now.addingTimeInterval(1800), title: "a")
        let clean = ScheduledBlock(
            taskID: UUID(),
            start: now.addingTimeInterval(3600),
            end: now.addingTimeInterval(5400),
            title: "b"
        )
        let items = DayTimelineLayout.items(
            forDay: now,
            events: [],
            blocks: [conflicted, clean],
            calendar: calendar,
            conflictedBlockIDs: [conflicted.id]
        )
        #expect(items.first { $0.blockID == conflicted.id }?.isConflicted == true)
        #expect(items.first { $0.blockID == clean.id }?.isConflicted == false)
    }

    @Test("call sites without a conflict set stay unconflicted (default parameter)")
    func defaultUnconflicted() {
        let block = ScheduledBlock(taskID: UUID(), start: now, end: now.addingTimeInterval(1800), title: "a")
        let items = DayTimelineLayout.items(forDay: now, events: [], blocks: [block], calendar: calendar)
        #expect(items.allSatisfy { !$0.isConflicted })
    }
}
