import Testing

@testable import NexusUI

/// Characterizes the trailing-edge debounce contract behind
/// `View.reloadOnStoreChange`: a burst of store-change events collapses to ONE
/// reload, while events spaced farther apart than the window each reload on
/// their own. The end state is unchanged versus per-event reloading; only the
/// count of intermediate reloads drops.
struct StoreChangeCoalescerTests {

    @Test("N events within the window collapse to a single trailing reload")
    func burstCollapsesToOne() {
        // Five saves 50ms apart (well inside the 400ms window): a sustained
        // burst. Only the last one survives "cancel + reschedule", firing once
        // 400ms after the final event.
        let events = [0, 50, 100, 150, 200]
        let fired = StoreChangeCoalescer.firedTimes(events: events, window: 400)
        #expect(fired == [600])
    }

    @Test("Events spaced wider than the window each reload independently")
    func spacedEventsEachFire() {
        // Three saves 500ms apart (> 400ms window): no coalescing — each is the
        // trailing edge of its own burst and fires once.
        let events = [0, 500, 1000]
        let fired = StoreChangeCoalescer.firedTimes(events: events, window: 400)
        #expect(fired == [400, 900, 1400])
    }

    @Test("A burst followed by a gap then another burst fires twice")
    func twoBurstsFireTwice() {
        // First burst at 0/100/200, quiet, second burst at 1000/1050. One
        // trailing reload per burst.
        let events = [0, 100, 200, 1000, 1050]
        let fired = StoreChangeCoalescer.firedTimes(events: events, window: 400)
        #expect(fired == [600, 1450])
    }

    @Test("A single event fires exactly once")
    func singleEventFiresOnce() {
        #expect(StoreChangeCoalescer.firedTimes(events: [42], window: 400) == [442])
    }

    @Test("No events fire nothing")
    func noEventsFireNothing() {
        #expect(StoreChangeCoalescer.firedTimes(events: [], window: 400).isEmpty)
    }

    @Test("Unsorted input is handled by arrival order")
    func unsortedInputIsSorted() {
        // Out-of-order timestamps still coalesce by true chronology.
        let events = [200, 0, 100]
        let fired = StoreChangeCoalescer.firedTimes(events: events, window: 400)
        #expect(fired == [600])
    }
}
