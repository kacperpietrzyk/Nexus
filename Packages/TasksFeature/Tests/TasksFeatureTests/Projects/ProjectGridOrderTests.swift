import Foundation
import NexusCore
import Testing
@testable import TasksFeature

@MainActor
@Suite struct ProjectGridOrderTests {
    private func project(
        _ name: String,
        status: ProjectStatus,
        pinned: Bool,
        updated: TimeInterval
    ) -> Project {
        let p = Project(name: name, color: "azure")
        p.statusRaw = status.rawValue
        p.isPinned = pinned
        p.updatedAt = Date(timeIntervalSince1970: updated)
        return p
    }

    @Test func pinnedComeFirst() {
        let pinned = project("Z-pinned", status: .backlog, pinned: true, updated: 1)
        let active = project("A-active", status: .active, pinned: false, updated: 100)
        let result = ProjectGridOrder.sorted([active, pinned])
        #expect(result.map(\.name) == ["Z-pinned", "A-active"])
    }

    @Test func activeBeforeOthersThenRecency() {
        let active = project("Active", status: .active, pinned: false, updated: 10)
        let doneRecent = project("DoneRecent", status: .completed, pinned: false, updated: 50)
        let doneOld = project("DoneOld", status: .completed, pinned: false, updated: 5)
        let result = ProjectGridOrder.sorted([doneOld, doneRecent, active])
        #expect(result.map(\.name) == ["Active", "DoneRecent", "DoneOld"])
    }
}
