import Foundation
import Testing

@testable import NexusAgent

@Test func threadListSortsByMostRecentUpdate() {
    let now = Date.now
    let t1 = AgentThread(title: "Old", updatedAt: now.addingTimeInterval(-3600))
    let t2 = AgentThread(title: "New", updatedAt: now)
    let t3 = AgentThread(title: "Middle", updatedAt: now.addingTimeInterval(-1800))
    let sorted = ThreadListView.sorted(threads: [t1, t2, t3])
    #expect(sorted.map(\.title) == ["New", "Middle", "Old"])
}

@Test func threadListBreaksUpdatedAtTiesByDescendingID() {
    let stamp = Date.now
    let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let higherID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
    let lower = AgentThread(id: lowerID, title: "Same", updatedAt: stamp)
    let higher = AgentThread(id: higherID, title: "Same", updatedAt: stamp)

    let sorted = ThreadListView.sorted(threads: [lower, higher])

    #expect(sorted.map(\.id) == [higherID, lowerID])
}

@Test func threadListFiltersArchivedFromActiveList() {
    let active = AgentThread(title: "Active")
    let archived = AgentThread(title: "Archived", archivedAt: .now)
    let filtered = ThreadListView.filterActive(threads: [active, archived])
    #expect(filtered.map(\.title) == ["Active"])
}
