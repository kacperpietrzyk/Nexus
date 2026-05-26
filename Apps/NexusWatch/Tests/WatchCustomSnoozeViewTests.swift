import Foundation
import Testing

@testable import NexusWatch

@Suite("WatchCustomSnoozeViewState")
@MainActor
struct WatchCustomSnoozeViewStateTests {

    @Test func quick_chip_one_hour_overrides_existing_selection() {
        let state = WatchCustomSnoozeViewState(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        state.selectedUntil = Date(timeIntervalSince1970: 0)  // known different baseline
        state.applyQuickChip(.oneHour)
        let expected = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(3_600)
        #expect(abs(state.selectedUntil.timeIntervalSince(expected)) < 1)
    }

    @Test func quick_chip_four_hours_sets_until() {
        let state = WatchCustomSnoozeViewState(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        state.applyQuickChip(.fourHours)
        let expected = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(4 * 3_600)
        #expect(abs(state.selectedUntil.timeIntervalSince(expected)) < 1)
    }

    @Test func quick_chip_tomorrow_uses_next_morning_nine() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = WatchCustomSnoozeViewState(now: { now })
        state.applyQuickChip(.tomorrow)
        let cal = Calendar.current
        let resultComponents = cal.dateComponents([.hour, .minute], from: state.selectedUntil)
        #expect(resultComponents.hour == 9)
        #expect(resultComponents.minute == 0)
    }

    @Test func datepicker_overrides_chip() {
        let state = WatchCustomSnoozeViewState(now: { Date() })
        state.applyQuickChip(.oneHour)
        let custom = Date().addingTimeInterval(7_200)
        state.selectedUntil = custom
        #expect(state.selectedUntil == custom)
    }
}
