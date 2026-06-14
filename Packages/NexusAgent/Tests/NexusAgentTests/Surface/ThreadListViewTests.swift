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

@Test func threadListBucketsByRelativeDayNewestFirst() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed reference
    let todayEarlier = now.addingTimeInterval(-3600)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
    let lastWeek = calendar.date(byAdding: .day, value: -6, to: now)!
    let archived = AgentThread(title: "Archived", updatedAt: now, archivedAt: now)

    let threads = [
        AgentThread(title: "Yesterday", updatedAt: yesterday),
        AgentThread(title: "Now", updatedAt: now),
        AgentThread(title: "Earlier today", updatedAt: todayEarlier),
        AgentThread(title: "Last week", updatedAt: lastWeek),
        archived,
    ]

    let groups = ThreadListView.bucketed(threads: threads, now: now, calendar: calendar)

    #expect(groups.map(\.bucket) == [.today, .yesterday, .earlier])
    // Today bucket is newest-first and excludes the archived thread.
    #expect(groups[0].threads.map(\.title) == ["Now", "Earlier today"])
    #expect(groups[1].threads.map(\.title) == ["Yesterday"])
    #expect(groups[2].threads.map(\.title) == ["Last week"])
}
