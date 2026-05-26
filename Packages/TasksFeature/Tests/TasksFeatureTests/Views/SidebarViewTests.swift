import Testing

@testable import TasksFeature

@Suite("TodayDashboard nav selection")
struct TodayDashboardNavSelectionTests {
    @Test("contains the v4 shell destinations")
    func destinations() {
        let destinations: [TodayNavSelection] = [
            .today, .inbox, .meetings, .tasks, .agent, .stats, .settings,
        ]
        #expect(destinations.count == 7)
        #expect(destinations.contains(.today))
        #expect(destinations.contains(.inbox))
        #expect(destinations.contains(.meetings))
        #expect(destinations.contains(.tasks))
        #expect(destinations.contains(.agent))
        #expect(destinations.contains(.stats))
        #expect(destinations.contains(.settings))
    }
}
