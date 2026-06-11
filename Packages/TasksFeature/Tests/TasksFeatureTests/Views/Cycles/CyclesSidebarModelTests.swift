import Foundation
import Testing

@testable import NexusCore
@testable import TasksFeature

@Suite("CyclesSidebarModel")
struct CyclesSidebarModelTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 86_400

    @MainActor
    private func makeCycle(
        _ name: String, status: CycleStatus, startOffsetDays: Double, endOffsetDays: Double, deleted: Bool = false
    ) -> Cycle {
        let cycle = Cycle(
            name: name,
            startAt: Self.now.addingTimeInterval(startOffsetDays * Self.day),
            endAt: Self.now.addingTimeInterval(endOffsetDays * Self.day)
        )
        cycle.statusRaw = status.rawValue
        if deleted { cycle.deletedAt = Self.now }
        return cycle
    }

    @MainActor
    @Test("display order: active first, then by startAt; completed and deleted excluded")
    func displayOrder() {
        let active = makeCycle("Current", status: .active, startOffsetDays: -7, endOffsetDays: 7)
        let upcomingNear = makeCycle("Next", status: .upcoming, startOffsetDays: 7, endOffsetDays: 14)
        let upcomingFar = makeCycle("Later", status: .upcoming, startOffsetDays: 14, endOffsetDays: 21)
        let completed = makeCycle("Shipped", status: .completed, startOffsetDays: -21, endOffsetDays: -7)
        let deleted = makeCycle("Gone", status: .upcoming, startOffsetDays: 7, endOffsetDays: 14, deleted: true)

        let ordered = CyclesSidebarModel.displayOrder([upcomingFar, completed, upcomingNear, deleted, active])
        #expect(ordered.map(\.name) == ["Current", "Next", "Later"])
    }

    @MainActor
    @Test("badges: containing active cycle is Current; earliest future upcoming is Next")
    func badges() {
        let active = makeCycle("Current", status: .active, startOffsetDays: -7, endOffsetDays: 7)
        let endedActive = makeCycle("Overrun", status: .active, startOffsetDays: -21, endOffsetDays: -7)
        let upcomingNear = makeCycle("Next", status: .upcoming, startOffsetDays: 7, endOffsetDays: 14)
        let upcomingFar = makeCycle("Later", status: .upcoming, startOffsetDays: 14, endOffsetDays: 21)
        let ordered = CyclesSidebarModel.displayOrder([active, endedActive, upcomingNear, upcomingFar])

        #expect(CyclesSidebarModel.badge(for: active, in: ordered, now: Self.now) == "Current")
        #expect(CyclesSidebarModel.badge(for: endedActive, in: ordered, now: Self.now) == nil)
        #expect(CyclesSidebarModel.badge(for: upcomingNear, in: ordered, now: Self.now) == "Next")
        #expect(CyclesSidebarModel.badge(for: upcomingFar, in: ordered, now: Self.now) == nil)
    }
}
