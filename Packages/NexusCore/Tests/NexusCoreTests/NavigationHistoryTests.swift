import Testing

@testable import NexusCore

@Suite struct NavigationHistoryTests {
    private func loc(_ d: String, _ detail: String? = nil) -> NavLocation {
        NavLocation(destinationToken: d, detailToken: detail)
    }

    @Test func visitPushesPreviousOntoBackAndClearsForward() {
        var h = NavigationHistory(current: loc("today"))
        h.visit(loc("tasks"))
        #expect(h.current == loc("tasks"))
        #expect(h.canGoBack)
        #expect(!h.canGoForward)
    }

    @Test func goBackThenForwardRoundTrips() {
        var h = NavigationHistory(current: loc("today"))
        h.visit(loc("tasks"))
        #expect(h.goBack() == loc("today"))
        #expect(h.current == loc("today"))
        #expect(h.canGoForward)
        #expect(h.goForward() == loc("tasks"))
        #expect(h.current == loc("tasks"))
    }

    @Test func visitingDuringForwardHistoryTruncatesForward() {
        var h = NavigationHistory(current: loc("today"))
        h.visit(loc("tasks"))
        _ = h.goBack()  // current = today, forward = [tasks]
        h.visit(loc("notes"))  // should discard the tasks forward entry
        #expect(!h.canGoForward)
        #expect(h.current == loc("notes"))
    }

    @Test func visitingSameLocationIsNoOp() {
        var h = NavigationHistory(current: loc("today"))
        h.visit(loc("today"))
        #expect(!h.canGoBack)
    }

    @Test func goBackAtRootReturnsNil() {
        var h = NavigationHistory(current: loc("today"))
        #expect(h.goBack() == nil)
    }
}
