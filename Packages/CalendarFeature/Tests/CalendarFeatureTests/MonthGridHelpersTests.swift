import Foundation
import Testing

@testable import CalendarFeature

/// Unit tests for `MonthGridHelpers` — pure partitioning + capacity logic that
/// supports `LiquidMonthGrid` without requiring a SwiftUI host.
@Suite struct MonthGridHelpersTests {
    let cal = Calendar(identifier: .gregorian)

    func makeItem(
        id: String = UUID().uuidString,
        isAllDay: Bool = false,
        kind: TimelineItem.Kind = .event
    ) -> TimelineItem {
        let base = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        return TimelineItem(
            id: id,
            title: id,
            start: base,
            end: cal.date(byAdding: .hour, value: 1, to: base)!,
            kind: kind,
            isAllDay: isAllDay
        )
    }

    // MARK: - timedItems

    @Test func timedItemsExcludesAllDay() {
        let timed = makeItem(id: "timed", isAllDay: false)
        let allDay = makeItem(id: "allday", isAllDay: true)
        let result = MonthGridHelpers.timedItems(from: [timed, allDay])
        #expect(result.count == 1)
        #expect(result[0].id == "timed")
    }

    @Test func timedItemsEmptyInputReturnsEmpty() {
        #expect(MonthGridHelpers.timedItems(from: []).isEmpty)
    }

    @Test func timedItemsAllAllDayReturnsEmpty() {
        let items = [makeItem(id: "a", isAllDay: true), makeItem(id: "b", isAllDay: true)]
        #expect(MonthGridHelpers.timedItems(from: items).isEmpty)
    }

    @Test func timedItemsPreservesOrder() {
        let items = (1...5).map { i in makeItem(id: "\(i)", isAllDay: false) }
        let result = MonthGridHelpers.timedItems(from: items)
        #expect(result.map(\.id) == items.map(\.id))
    }

    // MARK: - chipCapacity

    @Test func chipCapacityZeroHeightIsZero() {
        #expect(MonthGridHelpers.chipCapacity(availableHeight: 0) == 0)
    }

    @Test func chipCapacityExactlyOneChip() {
        // chipHeight = 14, chipSpacing = 1 → one chip fits in exactly 14 pt.
        #expect(MonthGridHelpers.chipCapacity(availableHeight: 14) == 1)
    }

    @Test func chipCapacityTwoChips() {
        // 14 (first) + 1 (spacing) + 14 (second) = 29 pt for two chips.
        #expect(MonthGridHelpers.chipCapacity(availableHeight: 29) == 2)
    }

    @Test func chipCapacityPartialSecondChipDoesNotCount() {
        // 14 + 1 + 13 = 28 — not enough for a second full chip.
        #expect(MonthGridHelpers.chipCapacity(availableHeight: 28) == 1)
    }

    @Test func chipCapacityThreeChips() {
        // 14 + (1+14) + (1+14) = 44 pt for three chips.
        #expect(MonthGridHelpers.chipCapacity(availableHeight: 44) == 3)
    }

    @Test func chipCapacityLargeHeight() {
        // 200 pt should fit plenty — just verify it grows linearly.
        let cap = MonthGridHelpers.chipCapacity(availableHeight: 200, chipHeight: 14, chipSpacing: 1)
        #expect(cap > 3)
    }
}
