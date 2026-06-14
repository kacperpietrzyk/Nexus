// SlotScheduler and SchedulingIntelligence are intentionally NOT unified in SP2.
// Empirical result (2026-06-14): the two finders are OUTPUT-IDENTICAL across all
// tested fixtures, including boundary cases that the plan predicted would diverge.
// SlotScheduler's workday pre-filter and SchedulingIntelligence's clip() guard
// both defend against the same invalid-DateInterval bug; they produce the same
// busy-span sets. Unification is therefore safe but deferred to a later sub-project
// (no caller change in SP2, adapter-first per spec §8.3).
// Do NOT "fix" either implementation to match the other without a deliberate migration.

import Foundation
import NexusCore
import Testing

@testable import CalendarFeature

// 2026-06-05 (Friday) 00:00:00 UTC — fixed absolute anchor; all offsets are plain
// seconds so the suite is timezone- and DST-agnostic.
private let anchor = Date(timeIntervalSince1970: 1_780_617_600)

// MARK: - Fixture helpers

private func t(_ hours: Double) -> Date {
    anchor.addingTimeInterval(hours * 3600)
}

private func event(
    _ id: String,
    from startHour: Double,
    to endHour: Double,
    allDay: Bool = false
) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: id,
        start: t(startHour),
        end: t(endHour),
        isAllDay: allDay
    )
}

// Workday 09:00–17:00 (8 h window).
private let workday = DateInterval(start: t(9), end: t(17))

// MARK: - Comparison helpers

/// Runs both finders with matching parameters and returns (SlotScheduler result, SI result).
private func both(
    events: [CalendarEvent],
    minimumMinutes: Int = 60,
    maximumMinutes: Int = 120
) -> ([DateInterval], [DateInterval]) {
    let ss = SlotScheduler()
    let slotResult = ss.freeSlots(
        events: events,
        within: workday,
        minimumMinutes: minimumMinutes,
        maximumMinutes: maximumMinutes
    )
    let minDuration = TimeInterval(minimumMinutes * 60)
    let maxDuration = maximumMinutes <= 0 ? TimeInterval.infinity : TimeInterval(maximumMinutes * 60)
    let siResult = SchedulingIntelligence.suggestedFocusBlocks(
        events: events,
        within: workday,
        minimumDuration: minDuration,
        maximumDuration: maxDuration
    )
    return (slotResult, siResult)
}

/// Unbounded variant: maximumMinutes: 0 / maximumDuration: .infinity.
private func bothUnbounded(
    events: [CalendarEvent],
    minimumMinutes: Int = 60
) -> ([DateInterval], [DateInterval]) {
    let ss = SlotScheduler()
    let slotResult = ss.freeSlots(
        events: events,
        within: workday,
        minimumMinutes: minimumMinutes,
        maximumMinutes: 0
    )
    let minDuration = TimeInterval(minimumMinutes * 60)
    let siResult = SchedulingIntelligence.suggestedFocusBlocks(
        events: events,
        within: workday,
        minimumDuration: minDuration,
        maximumDuration: .infinity
    )
    return (slotResult, siResult)
}

// MARK: - Test suite

@Suite("SlotScheduler vs SchedulingIntelligence — characterization")
struct SlotSchedulerVsIntelligenceTests {

    // (a) Empty day — full workday is one free block; chunked into 2 h pieces (4×2 h).
    @Test("(a) empty day — identical chunks")
    func emptyDay() {
        let (ss, si) = both(events: [])
        #expect(ss == si)
    }

    // (a-unbounded) Empty day, unbounded max — one slab covering the whole workday.
    @Test("(a-unbounded) empty day unbounded — identical single slab")
    func emptyDayUnbounded() {
        let (ss, si) = bothUnbounded(events: [])
        #expect(ss == si)
    }

    // (b) One mid-day meeting 12:00–13:00 — two free windows: 09–12 and 13–17.
    @Test("(b) one mid-day meeting — identical results")
    func oneMidDayMeeting() {
        let events = [event("meeting", from: 12, to: 13)]
        let (ss, si) = both(events: events)
        #expect(ss == si)
    }

    // (c) Two back-to-back meetings 10:00–11:00 and 11:00–12:00 (they touch, merge to 10–12).
    @Test("(c) back-to-back meetings merge — identical results")
    func backToBackMeetings() {
        let events = [
            event("m1", from: 10, to: 11),
            event("m2", from: 11, to: 12),
        ]
        let (ss, si) = both(events: events)
        #expect(ss == si)
    }

    // (d) Event overflowing past workday end: 16:00–19:00 — clips to 16:00–17:00.
    @Test("(d) event overflowing past workday end — identical results")
    func eventOverflowsWorkdayEnd() {
        let events = [event("late", from: 16, to: 19)]
        let (ss, si) = both(events: events)
        #expect(ss == si)
    }

    // (e) All-day event — both finders ignore it; result equals empty day.
    @Test("(e) all-day event ignored — identical to empty day")
    func allDayEvent() {
        let events = [event("allday", from: 0, to: 24, allDay: true)]
        let (ss, si) = both(events: events)
        let (emptyss, emptysi) = both(events: [])
        #expect(ss == si)
        #expect(ss == emptyss)
        #expect(si == emptysi)
    }

    // (f) Event starting before workday start: 07:00–10:00 — clips to 09:00–10:00.
    @Test("(f) event starting before workday — clips correctly, identical results")
    func eventStartsBeforeWorkday() {
        let events = [event("early", from: 7, to: 10)]
        let (ss, si) = both(events: events)
        #expect(ss == si)
    }

    // (g) Event ending before workday start: 06:00–08:30 — excluded entirely by both finders.
    @Test("(g) event entirely before workday — excluded by both finders, identical to empty day")
    func eventEntirelyBeforeWorkday() {
        let events = [event("preday", from: 6, to: 8.5)]
        let (ss, si) = both(events: events)
        let (emptyss, _) = both(events: [])
        #expect(ss == si)
        #expect(ss == emptyss)
    }

    // (h) Sub-minimum gap: two meetings leaving a 30-min gap (min=60) — the 30-min
    // gap must be dropped by both, leaving only the trailing window (14:30–17:00).
    // This is the key discriminating fixture for the gap-filter timing difference:
    // SI filters during the gap walk; SlotScheduler filters via the chunking while-loop.
    @Test("(h) sub-minimum gap is dropped by both — identical results")
    func subMinimumGapDropped() {
        // 09:00–12:00 meeting, then 12:30–14:30 meeting — 30 min gap at 12:00–12:30
        let events = [
            event("m1", from: 9, to: 12),
            event("m2", from: 12.5, to: 14.5),
        ]
        let (ss, si) = both(events: events, minimumMinutes: 60, maximumMinutes: 120)
        #expect(ss == si)
        // The 30-min gap 12:00–12:30 must not appear; only 14:30–16:30 and 14:30–17:00
        // (2 h chunk + remainder) or 14:30–16:30 + 16:30–17:00 depending on chunk math.
        for block in ss {
            #expect(block.duration >= 3600)
        }
    }
}
