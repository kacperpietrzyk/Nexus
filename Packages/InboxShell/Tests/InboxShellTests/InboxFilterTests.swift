import Foundation
import Testing
@testable import InboxShell

@Suite struct InboxFilterTests {
    private func item(_ s: FeedStream) -> FeedItem {
        FeedItem(key: UUID().uuidString, stream: s, title: "t", subtitle: nil,
                 createdAt: .init(timeIntervalSince1970: 0), route: .dailyBrief, iconName: "x")
    }
    @Test func allKeepsEverything() {
        let items = [item(.agent), item(.meeting), item(.bridge)]
        #expect(InboxFilter.all.apply(to: items).count == 3)
    }
    @Test func agentFiltersStreamAndExcludesBridge() {
        let items = [item(.agent), item(.meeting), item(.bridge)]
        #expect(InboxFilter.agent.apply(to: items).map(\.stream) == [.agent])
    }
    @Test func labels() {
        #expect(InboxFilter.allCases.map(\.displayLabel) == ["All", "Agent", "Meetings"])
    }
}
