import Testing

@testable import TasksFeature

@Suite("TodayNavSelection token round-trip")
struct TodayNavSelectionTokenTests {
    /// All 11 cases, listed explicitly (the enum is intentionally NOT CaseIterable).
    private let allCases: [TodayNavSelection] = [
        .today, .inbox, .meetings, .tasks, .projects, .notes,
        .calendar, .people, .agent, .stats, .settings,
    ]

    @Test func everyCaseTokenRoundTrips() {
        for sel in allCases {
            #expect(TodayNavSelection.from(token: sel.token) == sel)
        }
    }

    @Test func bogusTokenIsNil() {
        #expect(TodayNavSelection.from(token: "bogus") == nil)
    }

    @Test func tokensAreUnique() {
        let tokens = Set(allCases.map(\.token))
        #expect(tokens.count == allCases.count)
    }
}
