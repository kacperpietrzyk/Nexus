// Packages/InboxShell/Tests/InboxShellTests/FeedItemTests.swift
import Foundation
import Testing
@testable import InboxShell

@Suite struct FeedItemTests {
    private func item(seen: Date? = nil, dismissed: Date? = nil, snoozed: Date? = nil) -> FeedItem {
        FeedItem(
            key: "meeting:x", stream: .meeting, title: "T", subtitle: nil,
            createdAt: .init(timeIntervalSince1970: 0), route: .meeting(UUID()),
            iconName: "person.2", seenAt: seen, dismissedAt: dismissed, snoozedUntil: snoozed
        )
    }
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func unreadWhenNeverSeenAndVisible() {
        #expect(item().isUnread(now: now))
    }
    @Test func notUnreadOnceSeen() {
        #expect(!item(seen: now).isUnread(now: now))
    }
    @Test func dismissedIsNotVisibleNorUnread() {
        let it = item(dismissed: now)
        #expect(!it.isVisible(now: now))
        #expect(!it.isUnread(now: now))
    }
    @Test func snoozedInFutureHidden_pastVisible() {
        #expect(!item(snoozed: now.addingTimeInterval(60)).isVisible(now: now))
        #expect(item(snoozed: now.addingTimeInterval(-60)).isVisible(now: now))
    }
    @Test func idEqualsKey() {
        #expect(item().id == "meeting:x")
    }
}
