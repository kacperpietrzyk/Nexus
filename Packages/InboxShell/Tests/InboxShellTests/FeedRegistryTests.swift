// Packages/InboxShell/Tests/InboxShellTests/FeedRegistryTests.swift
import Foundation
import Testing

@testable import InboxShell

private struct StubProjector: FeedProjector {
    let stream: FeedStream
    let out: [FeedItem]
    func project() async throws -> [FeedItem] { out }
}

@Suite struct FeedRegistryTests {
    private func makeItem(_ key: String, _ stream: FeedStream, _ t: TimeInterval) -> FeedItem {
        FeedItem(
            key: key, stream: stream, title: key, subtitle: nil,
            createdAt: .init(timeIntervalSince1970: t),
            route: .dailyBrief, iconName: "x")
    }
    private let now = Date(timeIntervalSince1970: 10_000)

    @Test func joinsStateAndSortsNewestFirst() async throws {
        let registry = FeedRegistry()
        await registry.register(
            StubProjector(
                stream: .meeting,
                out: [
                    makeItem("a", .meeting, 1), makeItem("b", .meeting, 2),
                ]))
        await registry.setStateProvider { ["a": .init(seenAt: self.now, dismissedAt: nil, snoozedUntil: nil)] }
        let items = try await registry.items(now: now)
        #expect(items.map(\.key) == ["b", "a"])  // newest createdAt first
        #expect(items.first(where: { $0.key == "a" })?.seenAt != nil)
    }

    @Test func unreadExcludesBridgeAndSeenAndDismissed() async throws {
        let registry = FeedRegistry()
        await registry.register(StubProjector(stream: .meeting, out: [makeItem("m", .meeting, 1)]))
        await registry.register(StubProjector(stream: .bridge, out: [makeItem("bridge:unscheduled", .bridge, 9)]))
        await registry.setStateProvider { [:] }
        #expect(try await registry.unreadCount(now: now) == 1)  // meeting unread, bridge excluded
    }

    @Test func dismissedItemsAreFilteredOut() async throws {
        let registry = FeedRegistry()
        await registry.register(StubProjector(stream: .meeting, out: [makeItem("m", .meeting, 1)]))
        await registry.setStateProvider { ["m": .init(seenAt: nil, dismissedAt: self.now, snoozedUntil: nil)] }
        #expect(try await registry.items(now: now).isEmpty)
    }
}
